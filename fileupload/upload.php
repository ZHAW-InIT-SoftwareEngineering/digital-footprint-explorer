<?php
// Load the shared secret from dfe_uploads/.env (outside the web root)
$envFile = __DIR__ . '/../../dfe_uploads/.env';
$env = is_readable($envFile) ? parse_ini_file($envFile) : false;
$secret = is_array($env) ? (string)($env['UPLOAD_SECRET'] ?? '') : '';
if ($secret === '') {
    // Fail closed: never accept uploads without a configured secret
    error_log('upload.php: UPLOAD_SECRET missing or unreadable in ' . $envFile);
    http_response_code(500); exit('Server misconfigured');
}

// Shared-secret auth (constant-time comparison)
if (!hash_equals($secret, $_SERVER['HTTP_X_API_KEY'] ?? '')) {
    http_response_code(401); exit('Unauthorized');
}

if (!isset($_FILES['file']) || $_FILES['file']['error'] !== UPLOAD_ERR_OK) {
    http_response_code(400); exit('Upload error');
}

$f = $_FILES['file'];

// Size limit (e.g. 10 MB)
if ($f['size'] > 10 * 1024 * 1024) { http_response_code(413); exit('Too large'); }

// Check it's really a ZIP (magic bytes), not just the extension
$finfo = new finfo(FILEINFO_MIME_TYPE);
if ($finfo->file($f['tmp_name']) !== 'application/zip') {
    http_response_code(415); exit('Not a ZIP');
}

// Store outside the web root, with a server-generated name
$dir = __DIR__ . '/../../dfe_uploads/';
$name = bin2hex(random_bytes(16)) . '.zip';
if (!move_uploaded_file($f['tmp_name'], $dir . $name)) {
    http_response_code(500); exit('Save failed');
}

echo json_encode(['status' => 'ok', 'file' => $name]);