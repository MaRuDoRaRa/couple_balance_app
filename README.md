# Couple Balance App

夫婦で使える家計簿アプリです。夫と妻それぞれの金融機関の明細をCSVインポートして、月毎の支出を管理し、決められた割合で割り勘計算を行います。

## 主な機能

- **ユーザー選択**: 夫か妻かを選択してアプリを使用
- **CSVインポート**: 金融機関の明細をCSVファイルからインポート
- **支出管理**: 支出の追加、編集、削除
- **月別集計**: 月毎の支出合計とカテゴリ別集計
- **割り勘計算**: 設定した支払い割合に基づく割り勘額の表示
- **通知機能**: パートナーの支出変更をリアルタイム通知
- **手動入力**: 現金支出の手動登録

## 対応金融機関

### 銀行
- りそな銀行
- JRE Bank
- 楽天銀行

### クレジットカード
- JRE Viewカード
- 楽天カード

## 技術スタック

- **フロントエンド**: Flutter (Dart)
- **バックエンド**: Supabase (PostgreSQL)
- **認証**: Supabase Auth
- **リアルタイム**: Supabase Realtime
- **ストレージ**: Supabase Storage

## セットアップ

### 前提条件
- Flutter SDK 3.8.1以上
- Dart SDK
- Supabaseアカウント

### インストール手順

1. リポジトリをクローン
```bash
git clone <repository-url>
cd couple_balance_app
```

2. 依存関係をインストール
```bash
flutter pub get
```

3. Supabaseプロジェクトをセットアップ
   - [SUPABASE_SETUP.md](SUPABASE_SETUP.md) を参照

4. 環境変数を設定
   - `lib/config/supabase_config.dart` でSupabaseのURLとAPIキーを設定

5. アプリを実行
```bash
flutter run
```

## プロジェクト構造

```
lib/
├── config/
│   └── supabase_config.dart      # Supabase設定
├── models/
│   ├── user.dart                 # ユーザーモデル
│   ├── expense.dart              # 支出モデル
│   ├── category.dart             # カテゴリモデル
│   ├── notification.dart         # 通知モデル
│   └── csv_import_history.dart   # CSVインポート履歴モデル
├── services/
│   ├── supabase_service.dart     # Supabase操作
│   ├── csv_import_service.dart   # CSVインポート処理
│   └── notification_service.dart # 通知処理
└── main.dart                     # アプリケーションエントリーポイント
```

## データベース設計

### テーブル構成
- `users`: ユーザー情報（夫・妻）
- `expenses`: 支出データ
- `categories`: 支出カテゴリ
- `notifications`: 通知データ
- `csv_import_history`: CSVインポート履歴

### 主要な機能
- Row Level Security (RLS) によるデータ保護
- リアルタイム通知機能
- 自動更新タイムスタンプ
- 外部キー制約によるデータ整合性

## 開発ガイド

### 新しい金融機関の追加
1. `lib/services/csv_import_service.dart` に新しいパーサーを追加
2. `FinancialInstitution` enumに新しい機関を追加
3. CSVフォーマットに合わせてパーサーを実装

### 新しいカテゴリの追加
1. `lib/models/category.dart` の `ExpenseCategory` enumに追加
2. データベースの `expense_category` enumに追加
3. 初期データに新しいカテゴリを追加

## ライセンス

このプロジェクトはMITライセンスの下で公開されています。

## 貢献

プルリクエストやイシューの報告を歓迎します。大きな変更を行う場合は、まずイシューで議論してください。
