<?php
/** @var QJ\App $app */
use function QJ\{h, fmt};
$p = $app->progress;
$counts = $p->surahCounts($app->quran->surahs);
$cur = $p->next()['surah'] ?? null;
$complete = count(array_filter($app->quran->surahs, fn($s) => $counts[$s['number']] === $s['ayah_count']));
?>
<h1>Your journey</h1>
<div class="card row" style="margin-top:18px;gap:22px">
  <span class="ring big" style="--p:<?= round($p->fraction() * 100, 1) ?>"><b><?= number_format($p->fraction() * 100, 1) ?>%</b></span>
  <div class="stack">
    <p><span class="translation" style="font-size:24px"><?= fmt($p->completedVerses()) ?></span> <span class="muted">verses studied</span></p>
    <p><span class="translation" style="font-size:24px"><?= $complete ?></span> <span class="muted">surahs completed</span></p>
    <p><span class="translation" style="font-size:24px"><?= fmt(count($p->completedStudies())) ?></span> <span class="muted">of <?= fmt($app->plan->count()) ?> studies</span></p>
  </div>
</div>
<?php if ((int)$app->settings['journey'] > 1): ?><p class="faint" style="margin-top:10px">Journey <?= (int)$app->settings['journey'] ?></p><?php endif; ?>
<div class="section"><span class="label">All 114 surahs</span></div>
<div class="list">
<?php foreach ($app->quran->surahs as $s): $n = $counts[$s['number']]; $frac = $n / $s['ayah_count']; ?>
  <a href="/surah/<?= $s['number'] ?>" class="surah-row <?= $cur === $s['number'] ? 'current' : '' ?>">
    <span class="ring" style="--p:<?= round($frac * 100) ?>;width:38px;height:38px"><b style="font-size:12px"><?= $n === $s['ayah_count'] ? '✓' : $s['number'] ?></b></span>
    <span class="grow"><strong><?= h($s['name_translit']) ?></strong><?= $cur === $s['number'] ? ' <span class="tag accent">Now</span>' : '' ?><br>
      <span class="sub"><?= h($s['name_en']) ?> · <?= $s['ayah_count'] ?> verses<?= $n && $n < $s['ayah_count'] ? " · $n studied" : '' ?></span></span>
    <span class="arabic" style="font-size:20px;color:var(--ink-soft)"><?= h($s['name_ar']) ?></span>
  </a>
<?php endforeach; ?>
</div>
