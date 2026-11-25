<?php
/** @var QJ\App $app @var string $content @var string $title @var string $nav */
use function QJ\h;

$theme = $app->settings['theme'] ?? 'system';
$scale = (float)($app->settings['arabic_scale'] ?? 1);
$links = [
    'today' => ['/', 'Today', '<path d="M4 18h16M7 14a5 5 0 0 1 10 0M12 4v3M5.2 7.2l2 2M18.8 7.2l-2 2"/>'],
    'journey' => ['/journey', 'Journey', '<path d="M5 19c4 0 4-6 7-6s3-6 7-6"/><circle cx="5" cy="19" r="1.6"/><circle cx="12" cy="13" r="1.6"/><circle cx="19" cy="7" r="1.6"/>'],
    'library' => ['/library', 'Library', '<path d="M4 5.5C6.5 4.5 9.5 4.5 12 6c2.5-1.5 5.5-1.5 8-.5v13c-2.5-1-5.5-1-8 .5-2.5-1.5-5.5-1.5-8-.5z"/><path d="M12 6v13.5"/>'],
    'saved' => ['/saved', 'Saved', '<path d="M7 4h10v16l-5-3.5L7 20z"/>'],
    'settings' => ['/settings', 'You', '<path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/>'],
];
?><!doctype html>
<html lang="en" data-theme="<?= h($theme) ?>">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title><?= h($title ? "$title · " . QJ\App::NAME : QJ\App::NAME) ?></title>
<meta name="description" content="<?= h(QJ\App::TAGLINE) ?> A guided journey through the Quran.">
<meta name="theme-color" content="#FAF7F2" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#151216" media="(prefers-color-scheme: dark)">
<link rel="icon" href="/assets/mark.svg" type="image/svg+xml">
<link rel="preload" href="/assets/fonts/AmiriQuran-Regular.ttf" as="font" type="font/ttf" crossorigin>
<link rel="preload" href="/assets/fonts/Inter-Variable.ttf" as="font" type="font/ttf" crossorigin>
<link rel="stylesheet" href="/assets/app.css?v=2">
</head>
<body class="nav-<?= h($nav) ?>" data-arabic-scale="<?= h(number_format($scale, 1)) ?>">
<?php if ($nav !== 'none'): ?>
<header class="topbar">
  <a class="brand" href="/"><img src="/assets/mark.svg" alt="" width="28" height="28"><span><?= h(QJ\App::NAME) ?></span></a>
  <nav class="topnav" aria-label="Main">
    <?php foreach ($links as $k => [$href, $label]): ?>
      <a href="<?= $href ?>" class="<?= $nav === $k ? 'active' : '' ?>"><?= h($label) ?></a>
    <?php endforeach; ?>
  </nav>
</header>
<?php endif; ?>
<main class="main scale-<?= (int)round($scale * 10) ?>"><?= $content ?></main>
<?php if ($nav !== 'none'): ?>
<nav class="tabbar" aria-label="Main">
  <?php foreach ($links as $k => [$href, $label, $icon]): ?>
    <a href="<?= $href ?>" class="<?= $nav === $k ? 'active' : '' ?>">
      <svg viewBox="0 0 24 24" aria-hidden="true"><?= $icon ?></svg><span><?= h($label) ?></span>
    </a>
  <?php endforeach; ?>
</nav>
<?php endif; ?>
<script src="/assets/app.js?v=1" defer></script>
</body>
</html>
