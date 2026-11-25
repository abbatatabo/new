<?php
/** @var QJ\App $app @var string $q */
use QJ\App;
use function QJ\h;
$trId = (int)$app->translation()['id'];
?>
<h1>Library</h1>
<form method="get" action="/library" role="search" style="margin-top:14px">
  <label for="q" class="sr-only">Search</label>
  <input type="search" id="q" name="q" value="<?= h($q) ?>" placeholder="Surah, 2:255, Arabic or English words" autocomplete="off">
</form>
<?php if (mb_strlen($q) >= 2):
    $simple = fn($s) => preg_replace('/[^a-z0-9]/', '', strtolower($s));
    $surahs = array_filter($app->quran->surahs, fn($s) => ($simple($q) !== '' && str_contains($simple($s['name_translit']), $simple($q))) || stripos($s['name_en'], $q) !== false || str_contains($s['name_ar'], $q) || (string)$s['number'] === $q);
    $ids = $app->quran->search($q, $trId);
    $notes = array_filter($app->store->notes($app->profile), fn($n) => mb_stripos($n['text'], $q) !== false);
    $bms = array_filter($app->store->bookmarks($app->profile), fn($b) => mb_stripos((string)$b['label'], $q) !== false);
?>
  <?php if (!$surahs && !$ids && !$notes && !$bms): ?>
    <div class="card" style="margin-top:18px;text-align:center"><h3>Nothing found</h3><p class="muted">Try a surah name, a reference such as 2:255, or a word from the translation.</p></div>
  <?php endif; ?>
  <?php if ($surahs): ?><div class="section"><span class="label">Surahs</span></div><div class="list">
    <?php foreach ($surahs as $s): ?><a href="/read/<?= $s['number'] ?>"><span class="grow"><?= $s['number'] ?>. <?= h($s['name_translit']) ?><br><span class="sub"><?= h($s['name_en']) ?></span></span><span class="arabic" style="font-size:19px"><?= h($s['name_ar']) ?></span></a><?php endforeach; ?>
  </div><?php endif; ?>
  <?php if ($ids): $vs = []; foreach ($ids as $id) { $vs[] = $app->quran->verses($id, $id)[0]; } ?>
    <div class="section"><span class="label">Verses (<?= count($ids) ?><?= count($ids) >= 60 ? '+' : '' ?>)</span></div><div class="list">
    <?php foreach ($vs as $v): $t = $app->quran->text($trId, (int)$v['id'], (int)$v['id'])[(int)$v['id']] ?? ''; ?>
      <a href="/read/<?= $v['surah'] ?>?a=<?= $v['ayah'] ?>#a<?= $v['ayah'] ?>"><span class="grow"><strong><?= h($app->surahName((int)$v['surah'])) ?> <?= $v['surah'] ?>:<?= $v['ayah'] ?></strong><br><span class="sub"><?= h(mb_strimwidth($t, 0, 220, '…')) ?></span></span></a>
    <?php endforeach; ?></div>
  <?php endif; ?>
  <?php if ($bms): ?><div class="section"><span class="label">Saved</span></div><div class="list">
    <?php foreach ($bms as $b): ?><a href="<?= h(App::studyUrl($app->plan->forVerse((int)$b['verse_start']))) ?>"><span class="grow"><?= h($b['label']) ?></span></a><?php endforeach; ?></div><?php endif; ?>
  <?php if ($notes): ?><div class="section"><span class="label">Your reflections</span></div><div class="list">
    <?php foreach ($notes as $n): $st = $app->plan->forVerse((int)$n['study_start']); ?><a href="<?= h(App::studyUrl($st)) ?>?tab=reflect#notes"><span class="grow"><?= h(mb_strimwidth($n['text'], 0, 140, '…')) ?><br><span class="sub"><?= h($app->studyTitle($st)) ?></span></span></a><?php endforeach; ?></div><?php endif; ?>
<?php else: $done = array_slice($app->progress->completedStudies(), 0, 30); ?>
  <div class="section"><span class="label">Studied</span><span class="faint"><?= count($app->progress->completedStudies()) ?></span></div>
  <?php if (!$done): ?><p class="muted">Studies you complete are kept here to revisit.</p><?php else: ?>
    <div class="list"><?php foreach ($done as $st): ?><a href="<?= h(App::studyUrl($st)) ?>"><span class="grow">✓ <?= h($app->studyTitle($st)) ?></span><span class="chev">›</span></a><?php endforeach; ?></div>
  <?php endif; ?>
  <div class="section"><span class="label">Read the Quran</span></div>
  <div class="list"><?php foreach ($app->quran->surahs as $s): ?>
    <a href="/read/<?= $s['number'] ?>"><span class="faint" style="width:26px"><?= $s['number'] ?></span><span class="grow"><?= h($s['name_translit']) ?><br><span class="sub"><?= h($s['name_en']) ?> · <?= $s['ayah_count'] ?> verses</span></span><span class="arabic" style="font-size:19px;color:var(--ink-soft)"><?= h($s['name_ar']) ?></span></a>
  <?php endforeach; ?></div>
<?php endif; ?>
