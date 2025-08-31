-- Couple Balance App - Complete Database Schema
-- This file contains all migrations in one place

-- Enable Row Level Security
ALTER DATABASE postgres SET "app.jwt_secret" TO 'your-jwt-secret';

-- Create custom types
CREATE TYPE notification_type AS ENUM ('expense_added', 'expense_edited', 'expense_deleted');
CREATE TYPE role_type AS ENUM ('owner', 'member');


-- Users table (Supabase Authと連携)
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email VARCHAR(255) UNIQUE NOT NULL,
  nickname VARCHAR(50) NOT NULL,
  icon_url TEXT,
  color VARCHAR(7) DEFAULT '#3B82F6', -- ユーザーカラー（デフォルトは青）
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Households table (世帯管理)
CREATE TABLE households (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(100) NOT NULL,
  color VARCHAR(7) DEFAULT '#10B981', -- 世帯カラー（デフォルトは緑）
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Household Members table (世帯メンバー管理)
CREATE TABLE household_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_type role_type NOT NULL DEFAULT 'member',
  payment_ratio INTEGER NOT NULL CHECK (payment_ratio >= 0 AND payment_ratio <= 100),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(household_id, user_id)
);

-- Permission check function
CREATE OR REPLACE FUNCTION check_user_permission(
  target_household_id UUID,
  required_permission VARCHAR(100)
)
RETURNS BOOLEAN AS $$
DECLARE
  user_role role_type;
BEGIN
  -- ユーザーのロールを取得
  SELECT hm.role_type INTO user_role
  FROM household_members hm
  WHERE hm.household_id = target_household_id
    AND hm.user_id::text = auth.uid()::text
    AND hm.is_active = true;
  
  -- ロールが見つからない場合は権限なし
  IF user_role IS NULL THEN
    RETURN FALSE;
  END IF;
  
  -- 権限をチェック
  RETURN EXISTS (
    SELECT 1 FROM role_permissions rp
    WHERE rp.role_type = user_role
      AND rp.permission_name = required_permission
      AND rp.is_active = true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Payment ratio validation function
CREATE OR REPLACE FUNCTION validate_payment_ratio()
RETURNS TRIGGER AS $$
DECLARE
  total_ratio INTEGER;
BEGIN
  -- 同じ世帯のアクティブなメンバーの支払い比率の合計を計算
  SELECT COALESCE(SUM(payment_ratio), 0)
  INTO total_ratio
  FROM household_members
  WHERE household_id = NEW.household_id
    AND is_active = true
    AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000');

  -- 新しい比率を加算
  total_ratio := total_ratio + NEW.payment_ratio;

  -- 合計が100を超える場合はエラー
  IF total_ratio > 100 THEN
    RAISE EXCEPTION 'Payment ratio total cannot exceed 100. Current total: %, New ratio: %, Total would be: %', 
      total_ratio - NEW.payment_ratio, NEW.payment_ratio, total_ratio;
  END IF;

  -- 0%のメンバーが複数いる場合は警告（エラーにはしない）
  IF NEW.payment_ratio = 0 THEN
    RAISE NOTICE 'New member has 0%% payment ratio. Consider setting a proper ratio.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Payment ratio validation trigger
CREATE TRIGGER check_payment_ratio
  BEFORE INSERT OR UPDATE ON household_members
  FOR EACH ROW
  EXECUTE FUNCTION validate_payment_ratio();

-- Bulk expense import function
CREATE OR REPLACE FUNCTION bulk_import_expenses(
  p_household_id UUID,
  p_user_id UUID,
  p_expenses JSONB
)
RETURNS JSONB AS $$
DECLARE
  expense_record JSONB;
  inserted_expenses JSONB := '[]'::JSONB;
  success_count INTEGER := 0;
  error_count INTEGER := 0;
  error_messages TEXT[] := ARRAY[]::TEXT[];
  settlement_month DATE;
  settlement_status settlement_status;
BEGIN
  -- 精算確定済みかチェック
  FOR expense_record IN SELECT * FROM jsonb_array_elements(p_expenses)
  LOOP
    settlement_month := DATE_TRUNC('month', (expense_record->>'expense_date')::DATE);
    
    SELECT status INTO settlement_status
    FROM monthly_settlements
    WHERE household_id = p_household_id
      AND settlement_month = settlement_month
      AND status = 'settled';
    
    IF FOUND THEN
      RAISE EXCEPTION '精算確定済みの月の支出は追加できません: %', settlement_month;
    END IF;
  END LOOP;
  
  -- 一括挿入
  INSERT INTO expenses (
    household_id,
    user_id,
    sub_category_id,
    financial_institution_id,
    amount,
    description,
    expense_date,
    created_at,
    updated_at
  )
  SELECT
    p_household_id,
    p_user_id,
    (expense->>'sub_category_id')::UUID,
    (expense->>'financial_institution_id')::UUID,
    (expense->>'amount')::NUMERIC,
    expense->>'description',
    (expense->>'expense_date')::DATE,
    NOW(),
    NOW()
  FROM jsonb_array_elements(p_expenses) AS expense
  WHERE expense->>'is_valid' = 'true';
  
  GET DIAGNOSTICS success_count = ROW_COUNT;
  

  
  -- 結果を返す
  RETURN jsonb_build_object(
    'success_count', success_count,
    'error_count', error_count,
    'error_messages', error_messages,
    'success', true
  );
  
EXCEPTION
  WHEN OTHERS THEN
    -- エラーが発生した場合はロールバック
    RETURN jsonb_build_object(
      'success_count', 0,
      'error_count', jsonb_array_length(p_expenses),
      'error_messages', ARRAY[SQLERRM],
      'success', false
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;



-- Category Icons table (カテゴリアイコン集)
CREATE TABLE category_icons (
  id VARCHAR(50) PRIMARY KEY, -- アイコンID（例：'food', 'transport', 'entertainment'）
  name VARCHAR(100) NOT NULL, -- アイコン名
  description TEXT, -- アイコンの説明
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Categories table (メインカテゴリ)
CREATE TABLE categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  icon_id VARCHAR(50) NOT NULL REFERENCES category_icons(id),
  color VARCHAR(7) DEFAULT '#3B82F6', -- カテゴリの色（HEX）
  sort_order INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Sub Categories table (サブカテゴリ)
CREATE TABLE sub_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  sort_order INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Expenses table
CREATE TABLE expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sub_category_id UUID REFERENCES sub_categories(id) ON DELETE SET NULL,
  financial_institution_id UUID REFERENCES financial_institutions(id) ON DELETE SET NULL,
  amount DECIMAL(10,2) NOT NULL CHECK (amount > 0),
  description TEXT NOT NULL,
  expense_date DATE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);



-- Notifications table
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  from_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  notification_type notification_type NOT NULL,
  expense_id UUID REFERENCES expenses(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Financial Institutions master table
CREATE TABLE financial_institutions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code VARCHAR(50) UNIQUE NOT NULL, -- システム内コード
  name VARCHAR(100) NOT NULL, -- 表示名
  type VARCHAR(20) NOT NULL, -- 'bank' or 'credit_card'
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Role Permissions table for managing role-based permissions
CREATE TABLE role_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_type role_type NOT NULL,
  permission_name VARCHAR(100) NOT NULL,
  description TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(role_type, permission_name)
);

-- Household Invitations table for managing invitations
CREATE TABLE household_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invitation_code VARCHAR(50) UNIQUE NOT NULL,
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  is_used BOOLEAN DEFAULT FALSE,
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- CSV Import Patterns table for learning expense patterns
CREATE TABLE csv_import_patterns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  financial_institution_id UUID NOT NULL REFERENCES financial_institutions(id) ON DELETE CASCADE,
  sub_category_id UUID REFERENCES sub_categories(id) ON DELETE SET NULL,
  description TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);



-- Create indexes for better performance
CREATE INDEX idx_expenses_household_id ON expenses(household_id);
CREATE INDEX idx_expenses_user_id ON expenses(user_id);
CREATE INDEX idx_expenses_date ON expenses(expense_date);
CREATE INDEX idx_expenses_sub_category ON expenses(sub_category_id);
CREATE INDEX idx_expenses_financial_institution ON expenses(financial_institution_id);
CREATE INDEX idx_notifications_household_id ON notifications(household_id);
CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);
CREATE INDEX idx_household_members_household_id ON household_members(household_id);
CREATE INDEX idx_household_members_user_id ON household_members(user_id);
CREATE INDEX idx_category_icons_active ON category_icons(is_active);
CREATE INDEX idx_categories_household_id ON categories(household_id);
CREATE INDEX idx_categories_icon_id ON categories(icon_id);
CREATE INDEX idx_categories_sort_order ON categories(sort_order);
CREATE INDEX idx_sub_categories_household_id ON sub_categories(household_id);
CREATE INDEX idx_sub_categories_category_id ON sub_categories(category_id);
CREATE INDEX idx_sub_categories_sort_order ON sub_categories(sort_order);
CREATE INDEX idx_categories_updated_at ON categories(updated_at);
CREATE INDEX idx_sub_categories_updated_at ON sub_categories(updated_at);
CREATE INDEX idx_notifications_updated_at ON notifications(updated_at);
CREATE INDEX idx_financial_institutions_code ON financial_institutions(code);
CREATE INDEX idx_financial_institutions_active ON financial_institutions(is_active);
CREATE INDEX idx_csv_import_patterns_household_id ON csv_import_patterns(household_id);
CREATE INDEX idx_csv_import_patterns_user_institution ON csv_import_patterns(user_id, financial_institution_id);
CREATE INDEX idx_csv_import_patterns_sub_category ON csv_import_patterns(sub_category_id);
CREATE INDEX idx_csv_import_patterns_description ON csv_import_patterns(description);

CREATE INDEX idx_household_invitations_code ON household_invitations(invitation_code);
CREATE INDEX idx_household_invitations_expires ON household_invitations(expires_at);
CREATE INDEX idx_household_invitations_created_by ON household_invitations(created_by);
CREATE INDEX idx_role_permissions_role ON role_permissions(role_type);
CREATE INDEX idx_role_permissions_permission ON role_permissions(permission_name);
CREATE INDEX idx_role_permissions_active ON role_permissions(is_active);


-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_households_updated_at BEFORE UPDATE ON households
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_household_members_updated_at BEFORE UPDATE ON household_members
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_expenses_updated_at BEFORE UPDATE ON expenses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_category_icons_updated_at BEFORE UPDATE ON category_icons
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_categories_updated_at BEFORE UPDATE ON categories
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sub_categories_updated_at BEFORE UPDATE ON sub_categories
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_notifications_updated_at BEFORE UPDATE ON notifications
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_financial_institutions_updated_at BEFORE UPDATE ON financial_institutions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_csv_import_patterns_updated_at BEFORE UPDATE ON csv_import_patterns
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();



CREATE TRIGGER update_household_invitations_updated_at BEFORE UPDATE ON household_invitations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_role_permissions_updated_at BEFORE UPDATE ON role_permissions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();



-- Enable Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE households ENABLE ROW LEVEL SECURITY;
ALTER TABLE household_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE category_icons ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE sub_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE financial_institutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE csv_import_patterns ENABLE ROW LEVEL SECURITY;

ALTER TABLE household_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions ENABLE ROW LEVEL SECURITY;


-- Create RLS policies
-- Users can read their own user record
CREATE POLICY "Users can read own user" ON users FOR SELECT USING (auth.uid()::text = id::text);

-- Users can insert their own user record
CREATE POLICY "Users can insert own user" ON users FOR INSERT WITH CHECK (auth.uid()::text = id::text);

-- Users can update their own user record
CREATE POLICY "Users can update own user" ON users FOR UPDATE USING (auth.uid()::text = id::text);

-- Household policies
CREATE POLICY "Users can read households they belong to" ON households FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = households.id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
);

CREATE POLICY "Users can insert households" ON households FOR INSERT WITH CHECK (true);

CREATE POLICY "Users can update households they own" ON households FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = households.id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.role_type = 'owner'
    AND household_members.is_active = true
  )
);

-- Household members policies
CREATE POLICY "Users can read household members of their households" ON household_members FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM household_members hm
    WHERE hm.household_id = household_members.household_id 
    AND hm.user_id::text = auth.uid()::text
    AND hm.is_active = true
  )
);

CREATE POLICY "Users can insert household members" ON household_members FOR INSERT WITH CHECK (true);

CREATE POLICY "Users can update household members if owner" ON household_members FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM household_members hm
    WHERE hm.household_id = household_members.household_id 
    AND hm.user_id::text = auth.uid()::text
    AND hm.role_type = 'owner'
    AND hm.is_active = true
  )
  AND (
    -- 支払い比率の変更はオーナーのみ
    (household_members.payment_ratio IS DISTINCT FROM OLD.payment_ratio) = false
    OR EXISTS (
      SELECT 1 FROM household_members owner_check
      WHERE owner_check.household_id = household_members.household_id 
      AND owner_check.user_id::text = auth.uid()::text
      AND owner_check.role_type = 'owner'
      AND owner_check.is_active = true
    )
  )
);

-- Users can read expenses in their households (only active members' expenses)
CREATE POLICY "Users can read household expenses" ON expenses FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = expenses.household_id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
  AND EXISTS (
    SELECT 1 FROM household_members hm
    WHERE hm.household_id = expenses.household_id 
    AND hm.user_id = expenses.user_id
    AND hm.is_active = true
  )
);

-- Users can insert expenses in their households
CREATE POLICY "Users can insert household expenses" ON expenses FOR INSERT WITH CHECK (
  auth.uid()::text = user_id::text
  AND EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = expenses.household_id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
);

-- Users can update their own expenses in their households
CREATE POLICY "Users can update own household expenses" ON expenses FOR UPDATE USING (
  auth.uid()::text = user_id::text
  AND EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = expenses.household_id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
);

-- Users can delete their own expenses in their households
CREATE POLICY "Users can delete own household expenses" ON expenses FOR DELETE USING (
  auth.uid()::text = user_id::text
  AND EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = expenses.household_id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
);

-- Category Icons policies (readable by all users)
CREATE POLICY "Users can read category icons" ON category_icons FOR SELECT USING (true);

-- Categories policies (household-based)
CREATE POLICY "Users can read household categories" ON categories FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = categories.household_id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
);

CREATE POLICY "Users can insert household categories" ON categories FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = categories.household_id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
);

CREATE POLICY "Users can update household categories" ON categories FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = categories.household_id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
);

CREATE POLICY "Users can delete household categories" ON categories FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = categories.household_id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
);

-- Sub Categories policies (household-based)
CREATE POLICY "Users can read household sub categories" ON sub_categories FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = sub_categories.household_id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
);

CREATE POLICY "Users can insert household sub categories" ON sub_categories FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = sub_categories.household_id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
);

CREATE POLICY "Users can update household sub categories" ON sub_categories FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = sub_categories.household_id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
);

CREATE POLICY "Users can delete household sub categories" ON sub_categories FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = sub_categories.household_id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
);

-- Users can read notifications in their households
CREATE POLICY "Users can read household notifications" ON notifications FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM household_members 
    WHERE household_members.household_id = notifications.household_id 
    AND household_members.user_id::text = auth.uid()::text
    AND household_members.is_active = true
  )
);

-- Users can update their own notifications (mark as read)
CREATE POLICY "Users can update own notifications" ON notifications FOR UPDATE USING (auth.uid()::text = user_id::text);

-- Financial institutions are readable by all users
CREATE POLICY "Users can read financial institutions" ON financial_institutions FOR SELECT USING (true);

-- CSV import patterns policies (household-based)
CREATE POLICY "Users can read household csv import patterns" ON csv_import_patterns 
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM household_members 
      WHERE household_members.household_id = csv_import_patterns.household_id 
      AND household_members.user_id::text = auth.uid()::text
      AND household_members.is_active = true
    )
  );

CREATE POLICY "Users can insert household csv import patterns" ON csv_import_patterns 
  FOR INSERT WITH CHECK (
    auth.uid()::text = user_id::text
    AND EXISTS (
      SELECT 1 FROM household_members 
      WHERE household_members.household_id = csv_import_patterns.household_id 
      AND household_members.user_id::text = auth.uid()::text
      AND household_members.is_active = true
    )
  );

CREATE POLICY "Users can update household csv import patterns" ON csv_import_patterns 
  FOR UPDATE USING (
    auth.uid()::text = user_id::text
    AND EXISTS (
      SELECT 1 FROM household_members 
      WHERE household_members.household_id = csv_import_patterns.household_id 
      AND household_members.user_id::text = auth.uid()::text
      AND household_members.is_active = true
    )
  );

CREATE POLICY "Users can delete household csv import patterns" ON csv_import_patterns 
  FOR DELETE USING (
    auth.uid()::text = user_id::text
    AND EXISTS (
      SELECT 1 FROM household_members 
      WHERE household_members.household_id = csv_import_patterns.household_id 
      AND household_members.user_id::text = auth.uid()::text
      AND household_members.is_active = true
    )
  );



-- Insert default financial institutions
INSERT INTO financial_institutions (code, name, type) VALUES
  ('risona_bank', 'りそな銀行', 'bank'),
  ('jre_bank', 'JRE Bank', 'bank'),
  ('rakuten_bank', '楽天銀行', 'bank'),
  ('jre_view_card', 'JRE Viewカード', 'credit_card'),
  ('rakuten_card', '楽天カード', 'credit_card');

-- Insert default category icons
INSERT INTO category_icons (id, name, description) VALUES
  ('food', '食費', '食べ物や飲み物に関するアイコン'),
  ('transport', '交通費', '移動手段に関するアイコン'),
  ('entertainment', '娯楽費', '楽しみや趣味に関するアイコン'),
  ('shopping', '買い物', 'ショッピングに関するアイコン'),
  ('health', '医療費', '健康や医療に関するアイコン'),
  ('education', '教育費', '学習や教育に関するアイコン'),
  ('utilities', '光熱費', '電気・ガス・水道に関するアイコン'),
  ('housing', '住宅費', '住居に関するアイコン'),
  ('insurance', '保険料', '保険に関するアイコン'),
  ('other', 'その他', 'その他のアイコン'),
  ('cafe', 'カフェ', 'カフェや喫茶店に関するアイコン'),
  ('restaurant', '外食', 'レストランや外食に関するアイコン'),
  ('movie', '映画', '映画やエンターテイメントに関するアイコン'),
  ('game', 'ゲーム', 'ゲームや遊びに関するアイコン'),
  ('sport', 'スポーツ', '運動やスポーツに関するアイコン'),
  ('travel', '旅行', '旅行や観光に関するアイコン'),
  ('clothing', '衣類', '服やファッションに関するアイコン'),
  ('cosmetics', '化粧品', '美容や化粧品に関するアイコン'),
  ('electronics', '家電', '電化製品に関するアイコン'),
  ('medicine', '薬', '薬や医療品に関するアイコン'),
  ('book', '書籍', '本や読書に関するアイコン'),
  ('internet', 'インターネット', '通信やインターネットに関するアイコン'),
  ('car', '車', '自動車に関するアイコン'),
  ('gift', 'プレゼント', '贈り物に関するアイコン'),
  ('money', 'お金', '金銭に関するアイコン'),
  ('heart', '心', '愛情や感情に関するアイコン'),
  ('star', '星', '特別なものに関するアイコン');

-- Note: Default categories will be created by the application when a household is created
-- The application will create common categories like:
-- - 食費 (icon_id: 'food', with sub-categories: 食料品, 外食, カフェ, スイーツ, お酒)
-- - 交通費 (icon_id: 'transport', with sub-categories: 電車・バス, タクシー, ガソリン, 駐車場)
-- - 娯楽費 (icon_id: 'entertainment', with sub-categories: 映画, ゲーム, スポーツ, 旅行)
-- - 買い物 (icon_id: 'shopping', with sub-categories: 衣類, 雑貨, 化粧品, 家電)
-- - 医療費 (icon_id: 'health', with sub-categories: 病院, 薬, 歯科)
-- - 教育費 (icon_id: 'education', with sub-categories: 学費, 書籍, 習い事)
-- - 光熱費 (icon_id: 'utilities', with sub-categories: 電気, ガス, 水道, インターネット)
-- - 住宅費 (icon_id: 'housing', with sub-categories: 家賃, ローン, 管理費)
-- - 保険料 (icon_id: 'insurance', with sub-categories: 生命保険, 医療保険, 自動車保険)
-- - その他 (icon_id: 'other', with sub-categories: 未分類)

-- Note: Default users will be created when users sign up with Google Auth
-- Default households and members will be created by the application logic

-- Insert default role permissions
INSERT INTO role_permissions (role_type, permission_name, description) VALUES
  -- Owner permissions
  ('owner', 'household.delete', '世帯の削除'),
  ('owner', 'settlement.confirm', '精算の確定'),
  ('owner', 'settlement.cancel', '精算のキャンセル'),
  ('owner', 'settlement.unlock', '精算の解除'),
  ('owner', 'settlement.resettle', '精算の再確定'),
  ('owner', 'invitation.create', '招待URLの生成'),
  ('owner', 'payment_ratio.update', '支払い比率の変更'),
  ('owner', 'member.remove', 'メンバーの削除'),
  ('owner', 'ownership.transfer', 'オーナーの変更'),
  ('owner', 'category.manage', 'カテゴリの管理'),
  ('owner', 'expense.manage', '支出の管理（精算確定済み月も含む）'),
  
  -- Member permissions
  ('member', 'expense.create', '支出の作成'),
  ('member', 'expense.update', '支出の更新（精算未確定月のみ）'),
  ('member', 'expense.delete', '支出の削除（精算未確定月のみ）'),
  ('member', 'settlement.preview', '精算プレビューの確認'),
  ('member', 'notification.read', '通知の確認'),
  ('member', 'category.view', 'カテゴリの確認'),
  ('member', 'payment_ratio.view', '支払い比率の確認');

-- 月次精算確定テーブル
CREATE TABLE monthly_settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES households(id) ON DELETE CASCADE,
  settlement_month DATE NOT NULL, -- 精算対象月（YYYY-MM-01形式）
  total_amount INTEGER NOT NULL, -- その月の総支出額
  status settlement_status NOT NULL DEFAULT 'pending', -- 精算ステータス
  settled_at TIMESTAMP WITH TIME ZONE, -- 精算確定日時
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(household_id, settlement_month)
);

-- 月次精算メンバー詳細テーブル
CREATE TABLE monthly_settlement_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  monthly_settlement_id UUID NOT NULL REFERENCES monthly_settlements(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  payment_ratio INTEGER NOT NULL, -- 精算確定時の支払い比率
  actual_amount INTEGER NOT NULL, -- 実際の支出額
  calculated_amount INTEGER NOT NULL, -- 計算された精算額
  settlement_amount INTEGER NOT NULL, -- 最終精算額（calculated_amount - actual_amount）
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(monthly_settlement_id, user_id)
);

-- 精算ステータス列挙型
CREATE TYPE settlement_status AS ENUM ('pending', 'settled', 'cancelled');

-- インデックス
CREATE INDEX idx_monthly_settlements_household_month ON monthly_settlements(household_id, settlement_month);
CREATE INDEX idx_monthly_settlements_status ON monthly_settlements(status);
CREATE INDEX idx_monthly_settlement_members_settlement ON monthly_settlement_members(monthly_settlement_id);
CREATE INDEX idx_monthly_settlement_members_user ON monthly_settlement_members(user_id);

-- updated_atトリガー
CREATE TRIGGER update_monthly_settlements_updated_at
  BEFORE UPDATE ON monthly_settlements
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_monthly_settlement_members_updated_at
  BEFORE UPDATE ON monthly_settlement_members
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- RLSポリシー
ALTER TABLE monthly_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE monthly_settlement_members ENABLE ROW LEVEL SECURITY;

-- monthly_settlementsのRLSポリシー
CREATE POLICY "Users can view monthly settlements for their household" ON monthly_settlements
  FOR SELECT USING (
    household_id IN (
      SELECT household_id FROM household_members 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can insert monthly settlements for their household" ON monthly_settlements
  FOR INSERT WITH CHECK (
    household_id IN (
      SELECT household_id FROM household_members 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

CREATE POLICY "Users can update monthly settlements for their household" ON monthly_settlements
  FOR UPDATE USING (
    household_id IN (
      SELECT household_id FROM household_members 
      WHERE user_id = auth.uid() AND is_active = true
    )
  );

-- monthly_settlement_membersのRLSポリシー
CREATE POLICY "Users can view settlement members for their household" ON monthly_settlement_members
  FOR SELECT USING (
    monthly_settlement_id IN (
      SELECT id FROM monthly_settlements 
      WHERE household_id IN (
        SELECT household_id FROM household_members 
        WHERE user_id = auth.uid() AND is_active = true
      )
    )
  );

CREATE POLICY "Users can insert settlement members for their household" ON monthly_settlement_members
  FOR INSERT WITH CHECK (
    monthly_settlement_id IN (
      SELECT id FROM monthly_settlements 
      WHERE household_id IN (
        SELECT household_id FROM household_members 
        WHERE user_id = auth.uid() AND is_active = true
      )
    )
  );

CREATE POLICY "Users can update settlement members for their household" ON monthly_settlement_members
  FOR UPDATE USING (
    monthly_settlement_id IN (
      SELECT id FROM monthly_settlements 
      WHERE household_id IN (
        SELECT household_id FROM household_members 
        WHERE user_id = auth.uid() AND is_active = true
      )
    )
  );

-- household_invitationsのRLSポリシー
CREATE POLICY "Users can create invitations for their household" ON household_invitations
  FOR INSERT WITH CHECK (
    household_id IN (
      SELECT household_id FROM household_members 
      WHERE user_id = auth.uid() AND role_type = 'owner' AND is_active = true
    )
    AND created_by = auth.uid()
  );

CREATE POLICY "Users can read invitations they created" ON household_invitations
  FOR SELECT USING (
    created_by = auth.uid()
  );

CREATE POLICY "Anyone can read valid invitations by code" ON household_invitations
  FOR SELECT USING (
    is_used = false AND expires_at > NOW()
  );

CREATE POLICY "Users can update invitations they created" ON household_invitations
  FOR UPDATE USING (
    created_by = auth.uid()
  );

-- Role permissions policies (readable by all authenticated users)
CREATE POLICY "Users can read role permissions" ON role_permissions
  FOR SELECT USING (true);

-- Only system administrators can manage role permissions
CREATE POLICY "System admins can manage role permissions" ON role_permissions
  FOR ALL USING (
    auth.uid()::text IN (
      SELECT user_id::text FROM household_members 
      WHERE role_type = 'owner' 
      AND is_active = true
    )
  );




