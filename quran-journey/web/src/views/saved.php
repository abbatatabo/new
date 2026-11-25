<?php
/** @var QJ\App $app @var string $tab */
use QJ\App;
use function QJ\h;
$bms = $app->store->bookmarks($app->profile);
$csrf = h($app->csrf());
?>
<h1>Saved</h1>
<div class="segmented" style="margin-top:14px">
  <?php foreach (['verses' => 'Verses', 'studies' => 'Studies', 'reflections' => 'Reflections'] as $k => $l): ?><a href="/saved?tab=<?= $k ?>" class="<?= $tab === $k ? 'active' : '' ?>"><?= $l ?></a><?php endforeach; ?>
</div>
<?php if ($tab === 'reflections'): $notes = $app->store->notes($app->profile); ?>
  <?php if (!$notes): ?><div class="card" style="margin-top:18px;text-align:center"><h3>No reflections yet</h3><p class="muted">Write a reflection from the Reflect tab of any study. It stays private.</p></div><?php endif; ?>
  <div class="stack" style="margin-top:16px">
  <?php foreach ($notes as $n): $st = $app->plan->forVerse((int)$n['study_start']); ?>
    <div class="card"><p class="label"><?= h($app->studyTitle($st)) ?></p><p class="note" style="margin-top:6px"><?= h($n['text']) ?></p>
      <p style="margin-top:8px"><a href="<?= h(App::studyUrl($st)) ?>?tab=reflect#notes">Open study</a></p></div>
  <?php endforeach; ?>
  </div>
<?php else: $list = array_filter($bms, fn($b) => $tab === 'verses' ? $b['type'] === 'verse' : $b['type'] !== 'verse'); ?>
  <?php if (!$list): ?><div class="card" style="margin-top:18px;text-align:center"><h3><?= $tab === 'verses' ? 'No saved verses yet' : 'No saved studies yet' ?></h3><p class="muted">Tap the bookmark icon while studying to keep something here.</p></div>
  <?php else: ?>
  <div class="list" style="margin-top:16px">
    <?php foreach ($list as $b): $st = $app->plan->forVerse((int)$b['verse_start']); $ayah = $st['start_ayah'] + ((int)$b['verse_start'] - $st['start']); ?>
      <div>
        <a class="grow" href="<?= $b['type'] === 'verse' ? '/read/' . $st['surah'] . '?a=' . $ayah . '#a' . $ayah : h(App::studyUrl($st)) ?>"><?= h($b['label']) ?><br><span class="sub"><?= $b['type'] === 'verse' ? 'Verse' : 'Study' ?></span></a>
        <form method="post" action="/saved"><input type="hidden" name="_csrf" value="<?= $csrf ?>"><input type="hidden" name="tab" value="<?= h($tab) ?>"><input type="hidden" name="id" value="<?= (int)$b['id'] ?>">
          <button class="btn link" name="action" value="remove" aria-label="Remove <?= h($b['label']) ?>">Remove</button></form>
      </div>
    <?php endforeach; ?>
  </div>
  <?php endif; ?>
<?php endif; ?>
