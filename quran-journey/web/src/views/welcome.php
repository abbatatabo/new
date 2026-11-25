<?php
/** @var QJ\App $app @var int $step */
use QJ\App;
use function QJ\{h, hm};
$s = $app->settings;
$csrf = h($app->csrf());
?>
<div class="welcome">
  <div class="row">
    <div class="dots grow"><?php for ($i = 1; $i <= 4; $i++): ?><i class="<?= $i <= $step ? 'on' : '' ?>"></i><?php endfor; ?></div>
    <?php if ($step > 1): ?><a href="/welcome?step=<?= $step - 1 ?>">Back</a><?php endif; ?>
  </div>
  <form method="post" action="/welcome?step=<?= $step ?>" class="body stack" style="display:flex;flex-direction:column">
    <input type="hidden" name="_csrf" value="<?= $csrf ?>">
    <div class="grow stack">
    <?php if ($step === 1): ?>
      <img src="/assets/mark.svg" alt="" width="76" height="76">
      <p class="muted" style="font-weight:600;margin-top:28px"><?= h(App::NAME) ?></p>
      <h1 class="big">3 verses.<br>3 moments.<br>Every day.</h1>
      <p class="muted" style="font-size:17px;margin-top:18px">A calm, guided journey through the Quran, from Al-Fatihah to An-Nas. Each session brings you the next few verses to read, understand and reflect on.</p>
      <p class="muted">No ads. No streaks. No pressure. Miss a day and your journey simply waits for you.</p>
      <p class="faint">No account needed. Your progress is kept privately for this browser.</p>
    <?php elseif ($step === 2): ?>
      <h1>Your three moments</h1>
      <p class="muted">Pick times that already have a little space in them. You can change these whenever you like.</p>
      <?php foreach ($s['sessions'] as $sess): ?>
        <div class="card row">
          <label class="grow" for="t-<?= h($sess['id']) ?>"><strong><?= h($sess['label']) ?></strong></label>
          <input type="time" id="t-<?= h($sess['id']) ?>" name="time_<?= h($sess['id']) ?>" value="<?= hm((int)$sess['minutes']) ?>">
          <label class="switch" aria-label="<?= h($sess['label']) ?> on"><input type="checkbox" name="on_<?= h($sess['id']) ?>" value="1" <?= $sess['enabled'] ? 'checked' : '' ?>><span></span></label>
        </div>
      <?php endforeach; ?>
    <?php elseif ($step === 3):
        $v = $app->quran->verses(2, 2)[0];
        $t = $app->quran->text((int)$s['translation_id'], 2, 2)[2];
        $tl = $app->quran->text($app->quran->transliterationId(), 2, 2)[2];
    ?>
      <h1>Reading comfort</h1>
      <div class="card" style="text-align:center">
        <p class="quran" style="text-align:center"><?= h($v['text_uthmani']) ?></p>
        <?php if ($s['transliteration']): ?><p class="translit"><?= App::translit($tl) ?></p><?php endif; ?>
        <p class="translation" style="font-size:17px;margin-top:6px"><?= h($t) ?></p>
        <p class="faint" style="margin-top:4px">Al-Fatihah 1:2</p>
      </div>
      <label class="label" for="scale">Arabic size</label>
      <input type="range" id="scale" name="arabic_scale" min="0.8" max="1.8" step="0.1" value="<?= h($s['arabic_scale']) ?>">
      <div class="row"><span class="grow">Show transliteration</span><label class="switch"><input type="checkbox" name="transliteration" value="1" <?= $s['transliteration'] ? 'checked' : '' ?>><span></span></label></div>
      <p class="label">Translation</p>
      <div class="segmented"><?php foreach ($app->quran->englishTranslations() as $tr): ?><input type="radio" name="translation_id" id="tr<?= $tr['id'] ?>" value="<?= $tr['id'] ?>" <?= (int)$tr['id'] === (int)$s['translation_id'] ? 'checked' : '' ?>><label for="tr<?= $tr['id'] ?>"><?= h($tr['name']) ?></label><?php endforeach; ?></div>
      <p class="label">Theme</p>
      <div class="segmented"><?php foreach (['system' => 'System', 'light' => 'Light', 'dark' => 'Dark'] as $k => $l): ?><input type="radio" name="theme" id="th-<?= $k ?>" value="<?= $k ?>" <?= $s['theme'] === $k ? 'checked' : '' ?>><label for="th-<?= $k ?>"><?= $l ?></label><?php endforeach; ?></div>
    <?php else: $f = $app->quran->surah(1); ?>
      <p class="muted" style="font-size:17px">Your journey begins with</p>
      <p class="arabic" style="font-size:52px;color:var(--accent);line-height:1.4"><?= h($f['name_ar']) ?></p>
      <h1 class="big" style="margin-top:0">Al-Fatihah</h1>
      <p class="muted">The Opening · <?= $f['ayah_count'] ?> verses</p>
      <p class="muted" style="margin-top:20px">From here the journey goes through all 114 surahs in order, a few verses at a time, until An-Nas. Each study has the Arabic text, transliteration, translation, word-by-word analysis, context, tafsir sources and space for your own reflections.</p>
      <div class="notice">Reminders: a browser can't reliably wake you at a set time, so after starting you can add your three sessions to your phone's calendar from the Today page. Prefer the mobile app for built-in reminders and widgets.</div>
    <?php endif; ?>
    </div>
    <button class="btn block" style="margin-top:28px"><?= [1 => 'Begin', 2 => 'Continue', 3 => 'Continue', 4 => 'Start my journey'][$step] ?></button>
  </form>
</div>
