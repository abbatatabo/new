<?php
/** @var QJ\App $app @var int $n */
use QJ\App;
use function QJ\h;
$s = $app->quran->surah($n);
$studies = array_filter($app->plan->studies, fn($x) => $x['surah'] === $n);
$next = $app->progress->next();
?>
<p><a href="/journey">← Journey</a></p>
<div class="row" style="margin-top:10px"><div class="grow"><h1><?= h($s['name_translit']) ?></h1>
<p class="muted"><?= h($s['name_en']) ?> · <?= h($s['revelation_type']) ?> · <?= $s['ayah_count'] ?> verses · <?= count($studies) ?> studies</p></div>
<span class="arabic" style="font-size:30px;color:var(--ink-soft)"><?= h($s['name_ar']) ?></span></div>
<div class="list" style="margin-top:18px">
<?php foreach ($studies as $st): $done = $app->progress->isStudyComplete($st); $isNext = $next && $next['index'] === $st['index']; ?>
  <a href="<?= h(App::studyUrl($st)) ?>">
    <span class="slot-icon <?= $done || $isNext ? 'done' : '' ?>" style="width:34px;height:34px"><?= $done ? '✓' : ($isNext ? '●' : '○') ?></span>
    <span class="grow">Verses <?= $st['start_ayah'] ?><?= $st['end_ayah'] !== $st['start_ayah'] ? '–' . $st['end_ayah'] : '' ?><br>
      <span class="sub"><?= $done ? 'Completed' : ($isNext ? 'Next study' : 'Available to read ahead') ?></span></span>
    <span class="chev">›</span>
  </a>
<?php endforeach; ?>
</div>
<p style="margin-top:16px"><a href="/read/<?= $n ?>">Read the whole surah →</a></p>
