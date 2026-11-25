<?php
/** @var QJ\App $app */
use QJ\App;
use function QJ\{h, hm};
$s = $app->settings;
$csrf = h($app->csrf());
?>
<h1>You</h1>
<?php if (isset($_GET['saved'])): ?><div class="flash" style="margin-top:14px">Saved.</div><?php endif; ?>

<div class="section"><span class="label">Daily schedule</span></div>
<form method="post" action="/settings" class="card stack">
  <input type="hidden" name="_csrf" value="<?= $csrf ?>"><input type="hidden" name="action" value="schedule">
  <?php foreach ($s['sessions'] as $sess): ?>
    <div class="row">
      <label class="grow" for="t-<?= h($sess['id']) ?>"><?= h($sess['label']) ?></label>
      <input type="time" id="t-<?= h($sess['id']) ?>" name="time_<?= h($sess['id']) ?>" value="<?= hm((int)$sess['minutes']) ?>">
      <label class="switch" aria-label="<?= h($sess['label']) ?> on"><input type="checkbox" name="on_<?= h($sess['id']) ?>" value="1" <?= $sess['enabled'] ? 'checked' : '' ?>><span></span></label>
    </div>
  <?php endforeach; ?>
  <p class="faint">Times are in your time zone (<?= h($s['tz']) ?>).</p>
  <div><button class="btn">Save schedule</button></div>
</form>

<div class="section"><span class="label">Reminders</span></div>
<div class="card stack">
  <p>Add your sessions to your calendar as daily repeating events with an alert. This works on iPhone, Android and desktop, even when this site is closed.</p>
  <div><a class="btn ghost" href="/calendar.ics">Add to calendar (.ics)</a></div>
  <p class="faint">If you change your times, download the file again and remove the old events. For reminders and home-screen widgets built in, use the mobile app.</p>
</div>

<div class="section"><span class="label">Reading &amp; appearance</span></div>
<form method="post" action="/settings" class="card stack">
  <input type="hidden" name="_csrf" value="<?= $csrf ?>"><input type="hidden" name="action" value="reading">
  <label class="label" for="tr">Translation</label>
  <select id="tr" name="translation_id"><?php foreach ($app->quran->englishTranslations() as $t): ?><option value="<?= $t['id'] ?>" <?= (int)$t['id'] === (int)$s['translation_id'] ? 'selected' : '' ?>><?= h($t['name'] . ' — ' . $t['translator']) ?></option><?php endforeach; ?></select>
  <div class="row"><span class="grow">Show transliteration</span><label class="switch"><input type="checkbox" name="transliteration" value="1" <?= $s['transliteration'] ? 'checked' : '' ?>><span></span></label></div>
  <label class="label" for="scale">Arabic text size</label>
  <input type="range" id="scale" name="arabic_scale" min="0.8" max="1.8" step="0.1" value="<?= h($s['arabic_scale']) ?>">
  <label class="label" for="rec">Reciter</label>
  <select id="rec" name="reciter"><?php foreach (App::RECITERS as $k => $name): ?><option value="<?= h($k) ?>" <?= $k === $s['reciter'] ? 'selected' : '' ?>><?= h($name) ?></option><?php endforeach; ?></select>
  <label class="label" for="vps">Verses per study</label>
  <select id="vps" name="verses_per_study"><?php foreach ([1 => '1 verse', 2 => '2 verses', 3 => '3 verses (recommended)', 5 => '5 verses'] as $k => $l): ?><option value="<?= $k ?>" <?= $k === (int)$s['verses_per_study'] ? 'selected' : '' ?>><?= $l ?></option><?php endforeach; ?></select>
  <p class="faint">Changing this regroups future studies; verses you have studied stay studied.</p>
  <div class="row"><span class="grow">Online study sources<br><span class="faint">Word meanings and classical tafsir from Quran.com</span></span><label class="switch"><input type="checkbox" name="online" value="1" <?= $s['online'] ? 'checked' : '' ?>><span></span></label></div>
  <p class="label">Theme</p>
  <div class="segmented"><?php foreach (['system' => 'System', 'light' => 'Light', 'dark' => 'Dark'] as $k => $l): ?><input type="radio" name="theme" id="th-<?= $k ?>" value="<?= $k ?>" <?= $s['theme'] === $k ? 'checked' : '' ?>><label for="th-<?= $k ?>"><?= $l ?></label><?php endforeach; ?></div>
  <div><button class="btn">Save</button></div>
</form>

<div class="section" id="device"><span class="label">Use on another device</span></div>
<div class="card stack">
  <p>There's no account. Your journey is tied to this browser. To continue on another device, enter this transfer code there:</p>
  <p class="js-reveal" data-code="<?= h($app->transferCode()) ?>"><button type="button" class="btn ghost">Show my transfer code</button></p>
  <p class="faint">Keep it private: anyone with the code can see your reflections.</p>
  <form method="post" action="/settings" class="stack">
    <input type="hidden" name="_csrf" value="<?= $csrf ?>"><input type="hidden" name="action" value="restore">
    <label class="label" for="code">Have a code from another device?</label>
    <input type="text" id="code" name="code" autocomplete="off" spellcheck="false" placeholder="XXXXXX-XXXXXX-…">
    <?php if (($_GET['err'] ?? '') === 'code'): ?><p class="faint" style="color:#B3261E">That code wasn't recognised.</p><?php endif; ?>
    <p class="faint">This browser's current journey will be replaced by the other device's journey.</p>
    <div><button class="btn ghost">Use this code</button></div>
  </form>
</div>

<div class="section"><span class="label">Your data</span></div>
<div class="list">
  <a href="/export.json"><span class="grow">Export my data<br><span class="sub">Progress, reflections and saved items as JSON</span></span><span class="chev">↓</span></a>
  <form method="post" action="/settings"><input type="hidden" name="_csrf" value="<?= $csrf ?>"><input type="hidden" name="action" value="erase">
    <button class="btn link" style="padding:0" data-confirm="Erase your journey, reflections and saved items permanently?">Erase all my data</button></form>
</div>

<div class="section"><span class="label">About</span></div>
<div class="list">
  <a href="/sources"><span class="grow">Sources &amp; methodology</span><span class="chev">›</span></a>
  <a href="/privacy"><span class="grow">Privacy</span><span class="chev">›</span></a>
  <div><span class="grow"><?= h(App::NAME) ?><br><span class="sub"><?= h(App::TAGLINE) ?> · Content version <?= h($app->quran->meta['content_version'] ?? '') ?></span></span></div>
</div>
