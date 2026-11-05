<?php
declare(strict_types=1);

$config = require '/etc/ovpc/db.php';

try {
    $db = new PDO(
        sprintf('mysql:host=%s;dbname=%s;charset=utf8mb4', $config['host'], $config['dbname']),
        $config['user'],
        $config['pass'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );

    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $message = trim((string) ($_POST['message'] ?? ''));
        if ($message !== '' && strlen($message) <= 255) {
            $stmt = $db->prepare('INSERT INTO notes (message) VALUES (:message)');
            $stmt->execute(['message' => $message]);
        }
        header('Location: /index.php', true, 303);
        exit;
    }

    $rows = $db->query('SELECT id, message, created_at FROM notes ORDER BY id DESC LIMIT 20')->fetchAll();
} catch (PDOException $e) {
    error_log('oVPC lab database error: ' . $e->getMessage());
    http_response_code(503);
    exit('Database connection failed');
}

function e(string $value): string {
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
?>
<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>oVPC LEMP Lab</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 760px; margin: 32px auto; padding: 0 18px; line-height: 1.5; }
    input { padding: 10px; width: min(380px, 65%); }
    button { padding: 10px 18px; cursor: pointer; }
    li { margin: 8px 0; overflow-wrap: anywhere; }
    small { color: #666; }
  </style>
</head>
<body>
  <h1>Website oVPC LEMP Stack</h1>
  <p>Web server: <strong><?= e(gethostname() ?: 'unknown') ?></strong></p>
  <p>Database: <strong>labdb</strong> (dùng chung cho các Web VM)</p>
  <form method="post" action="/index.php">
    <label for="message">Nội dung ghi chú</label><br>
    <input id="message" name="message" maxlength="255" required>
    <button type="submit">Lưu vào MySQL</button>
  </form>
  <h2>20 bản ghi gần nhất</h2>
  <ul>
    <?php foreach ($rows as $row): ?>
      <li><?= e((string) $row['message']) ?> <small>#<?= (int) $row['id'] ?> · <?= e((string) $row['created_at']) ?></small></li>
    <?php endforeach; ?>
  </ul>
</body>
</html>
