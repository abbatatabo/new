<?php
/** @var QJ\App $app */
use QJ\App;
use QJ\Plan;
use function QJ\{h, fmt};
require_once __DIR__ . '/_icons.php';

$now = $app->now();
$p = $app->progress;
$next = $p->next();
$slots = $p->today($app->settings['sessions'], $now);
$doneToday = count(array_filter($slots, fn($s) => $s['state'] === 'done'));
$lastAt = $p->completions ? end($p->completions)['completed_at'] : null;
$away = $lastAt !== null && (time() - intdiv($lastAt, 1000)) >= 3 * 86400;
$h = (int)$now->format('G');
$greeting = $h < 5 ? 'Peaceful night' : ($h < 12 ? 'Good morning' : ($h < 17 ? 'Good afternoon' : 'Good evening'));
$sub = $away ? 'Welcome back. Your journey is right where you left it.'
    : ($next === null ? 'You have completed the journey through the whole Quran.'
    : ($slots && $doneToday >= count($slots) ? "Today's moments are complete. May they stay with you." : App::TAGLINE));
?>
<?php if (isset($_GET['restored'])): ?><div class="flash">This browser now uses your journey from the other device.</div><?php endif; ?>
<h1><?= h($greeting) ?></h1>
<p class="muted" style="margin-top:6px"><?= h($sub) ?></p>

<?php if ($next): $s = $app->quran->surah($next['surah']); $first = $app->quran->verses($next['start'], $next['start'])[0]; ?>
<a class="hero" href="<?= h(App::studyUrl($next)) ?>" style="margin-top:22px">
  <div class="row"><span class="label grow"><?= $p->completedVerses() ? 'Your next study' : 'Your journey begins' ?></span><span class="arabic" style="font-size:22px"><?= h($s['name_ar']) ?></span></div>
  <h2><?= h($s['name_translit']) ?></h2>
  <div class="sub"><?= h($s['name_en']) ?> · <?= $next['start_ayah'] === $next['end_ayah'] ? 'Verse ' . $next['start_ayah'] : "Verses {$next['start_ayah']}–{$next['end_ayah']}" ?></div>
  <?php if (mb_strlen($first['text_uthmani']) <= 90): ?>
    <div class="quran"><?= h($first['text_uthmani']) ?></div>
  <?php else: ?>
    <p style="margin-top:14px;font-family:Newsreader,serif;font-style:italic;opacity:.9">Begins at <?= h($s['name_translit']) ?> <?= $first['surah'] ?>:<?= $first['ayah'] ?></p>
  <?php endif; ?>
  <div class="row" style="margin-top:14px"><span class="grow sub"><?= $next['end'] - $next['start'] + 1 ?> verses · about <?= 3 + ($next['end'] - $next['start'] + 1) * 2 ?> min</span><span class="pill"><?= $p->completedVerses() ? 'Continue' : 'Begin' ?></span></div>
</a>
<?php else: ?>
<div class="card stack" style="margin-top:22px">
  <h2>Alhamdulillah</h2>
  <p class="muted">You have studied every verse from Al-Fatihah to An-Nas. You may begin the journey again whenever you wish.</p>
  <form method="post" action="/settings"><input type="hidden" name="_csrf" value="<?= h($app->csrf()) ?>"><input type="hidden" name="action" value="new_journey"><button class="btn ghost">Begin a new journey</button></form>
</div>
<?php endif; ?>

<div class="section"><span class="label">Today</span><span class="faint"><?= $doneToday ?> of <?= count($slots) ?></span></div>
<?php if (!$slots): ?><p class="muted">No sessions are enabled. You can still read any time, or enable sessions under You.</p><?php endif; ?>
<div class="stack">
<?php foreach ($slots as $slot): $st = $slot['state']; ?>
  <a class="card row" href="<?= h(App::studyUrl($slot['study'])) ?>" style="padding:14px 16px">
    <span class="slot-icon <?= $st === 'done' ? 'done' : '' ?>"><?= qj_icon($st === 'done' ? 'check' : $slot['session']['id']) ?></span>
    <span class="grow"><strong><?= h($slot['session']['label']) ?></strong><br><span class="muted" style="font-size:14px"><?= h($app->studyTitle($slot['study'])) ?></span></span>
    <span class="state-<?= $st ?>"><?= $st === 'done' ? 'Completed' : ($st === 'ready' ? 'Ready' : 'At ' . QJ\hm($slot['session']['minutes'])) ?></span>
  </a>
<?php endforeach; ?>
</div>
<?php if ($next && $slots && $doneToday >= count($slots)): ?>
  <p style="margin-top:12px"><a href="<?= h(App::studyUrl($next)) ?>">Continue to <?= h($app->studyTitle($next)) ?> →</a></p>
<?php endif; ?>

<div class="section"><span class="label">Journey</span></div>
<a class="card row" href="/journey">
  <span class="ring" style="--p:<?= round($p->fraction() * 100, 1) ?>"><b><?= number_format($p->fraction() * 100, $p->fraction() < 0.1 ? 1 : 0) ?>%</b></span>
  <span class="grow"><strong><?= fmt($p->completedVerses()) ?> of <?= fmt($app->plan->totalVerses) ?> verses</strong><br>
  <span class="muted" style="font-size:14px"><?= $next ? 'Now in ' . h($app->surahName($next['surah'])) . " · Surah {$next['surah']} of 114" : 'Journey complete' ?></span></span>
  <span class="chev"><?= qj_icon('chev') ?></span>
</a>
<p class="faint" style="margin-top:22px">Want reminders? <a href="/calendar.ics">Add your three daily sessions to your calendar</a>. Calendar apps notify you reliably, even with the browser closed.</p>
