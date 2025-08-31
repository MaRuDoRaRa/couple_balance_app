# Couple Balance App - Supabase セットアップ手順

## 1. Supabaseプロジェクトの作成

1. [Supabase](https://supabase.com) にアクセスしてアカウントを作成
2. 新しいプロジェクトを作成
3. プロジェクト名: `couple-balance-app`
4. データベースパスワードを設定（安全なパスワードを使用）

## 2. データベーススキーマの適用

1. Supabaseダッシュボードで「SQL Editor」を開く
2. `supabase/migrations/001_initial_schema_with_patterns.sql` の内容をコピー
3. SQL Editorに貼り付けて実行

## 3. 環境変数の設定

1. Supabaseダッシュボードで「Settings」→「API」を開く
2. 以下の情報をコピー：
   - Project URL
   - anon public key

3. `lib/config/supabase_config.dart` を編集：
```dart
static const String supabaseUrl = 'YOUR_PROJECT_URL';
static const String supabaseAnonKey = 'YOUR_ANON_KEY';
```

## 4. Row Level Security (RLS) の確認

データベーススキーマでRLSが有効になっていることを確認：
- すべてのテーブルでRLSが有効
- 適切なポリシーが設定済み

## 5. 認証設定（オプション）

必要に応じて認証機能を追加：
1. Supabaseダッシュボードで「Authentication」→「Settings」
2. 必要な認証プロバイダーを設定

## 6. ストレージ設定（オプション）

ユーザーアイコン用のストレージバケットを作成：
1. Supabaseダッシュボードで「Storage」
2. 新しいバケット `user-icons` を作成
3. 適切なRLSポリシーを設定

## 7. リアルタイム機能の設定

通知のリアルタイム更新のため：
1. Supabaseダッシュボードで「Database」→「Replication」
2. `notifications` テーブルでリアルタイムを有効化

## 8. テストデータの確認

初期データが正しく挿入されていることを確認：
- カテゴリ（食費、交通費など）
- デフォルトユーザー（夫、妻）

## 9. アプリケーションの実行

1. Flutterアプリを実行
2. Supabaseとの接続をテスト
3. 基本的なCRUD操作をテスト

## トラブルシューティング

### 接続エラー
- URLとAPIキーが正しいことを確認
- ネットワーク接続を確認

### RLSエラー
- ポリシーが正しく設定されていることを確認
- ユーザーIDが正しく設定されていることを確認

### CSVインポートエラー
- ファイル形式が正しいことを確認
- 金融機関のCSVフォーマットに合わせてパーサーを調整

## セキュリティ注意事項

1. APIキーを公開リポジトリにコミットしない
2. 本番環境では適切な認証を実装
3. データベースのバックアップを定期的に実行
4. ログを監視して異常なアクセスを検出

## パフォーマンス最適化

1. インデックスが正しく作成されていることを確認
2. 大量データの場合はページネーションを実装
3. キャッシュ戦略を検討
4. クエリの最適化
