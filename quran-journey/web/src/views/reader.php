<?php
/** @var QJ\App $app @var int $n @var int $ayah */
use QJ\App;
use function QJ\h;
$s = $app->quran->surah($n);
$verses = $app->quran->verses((int)$s['first_verse_id'], (int)$s['first_verse_id'] + (int)$s['ayah_count'] - 1);
$tr = $app->quran->text((int)$app->translation()['id'], (int)$s['first_verse_id'], (int)$s['first_verse_id'] + (int)$s['ayah_count'] - 1);
$tl = $app->settings['transliteration'] ? $app->quran->text($app->quran->transliterationId(), (int)$s['first_verse_id'], (int)$s['first_verse_id'] + (int)$s['ayah_count'] - 1) : [];
?>
<p><a href="/library">← Library</a></p>
<div style="text-align:center;margin-top:10px">
  <p class="arabic" style="font-size:36px;line-height:1.5"><?= h($s['name_ar']) ?></p>
  <h1><?= h($s['name_translit']) ?></h1>
  <p class="faint"><?= h($s['name_en']) ?> · <?= h($s['revelation_type']) ?> · <?= $s['ayah_count'] ?> verses · reading here does not change your journey progress</p>
  <?php if (!empty($verses[0]['bismillah'])): ?><p class="quran" style="text-align:center;color:var(--ink-soft);margin-top:12px"><?= h($verses[0]['bismillah']) ?></p><?php endif; ?>
</div>
<?php foreach ($verses as $v): $vid = (int)$v['id']; $st = $app->plan->forVerse($vid); ?>
  <article class="verse<?= $ayah === (int)$v['ayah'] ? ' playing' : '' ?>" id="a<?= $v['ayah'] ?>" style="border-bottom:1px solid var(--line);border-radius:0">
    <div class="tools"><span class="tag"><?= $v['surah'] ?>:<?= $v['ayah'] ?></span><?= $app->progress->isVerseComplete($vid) ? ' <span class="state-done">✓</span>' : '' ?><span class="grow"></span><a href="<?= h(App::studyUrl($st)) ?>">Study</a></div>
    <p class="quran" lang="ar"><?= h($v['text_uthmani']) ?> <span class="mark"><?= App::ayahMark((int)$v['ayah']) ?></span></p>
    <?php if ($tl): ?><p class="translit"><?= App::translit($tl[$vid] ?? '') ?></p><?php endif; ?>
    <p class="translation" style="font-size:18px"><?= h($tr[$vid] ?? '') ?></p>
  </article>
<?php endforeach; ?>
<?php if ($n < 114): ?><p style="margin-top:20px;text-align:right"><a href="/read/<?= $n + 1 ?>">Next: <?= h($app->surahName($n + 1)) ?> →</a></p><?php endif; ?>
