<?php
/** @var QJ\App $app @var array $study @var string $tab */
use QJ\App;
use QJ\Plan;
use QJ\Online;
use QJ\Morphology;
use function QJ\h;
require_once __DIR__ . '/_icons.php';

$q = $app->quran;
$surah = $q->surah($study['surah']);
$verses = $q->verses($study['start'], $study['end']);
$tr = $app->translation();
$texts = $q->text((int)$tr['id'], $study['start'], $study['end']);
$tl = $q->text($q->transliterationId(), $study['start'], $study['end']);
$p = $app->profile;
$done = $app->progress->isStudyComplete($study);
$url = App::studyUrl($study);
$csrf = h($app->csrf());
$online = (bool)$app->settings['online'];
$cms = $online ? $app->online->cms($study['surah'], $study['start_ayah'], $study['end_ayah']) : [];
$cats = ['direct_quotation' => 'Direct quotation', 'paraphrase' => 'Paraphrase', 'editorial_summary' => 'Editorial summary', 'ai_assisted' => 'AI-assisted explanation'];
$catHelp = [
    'direct_quotation' => 'The exact words of the named work.',
    'paraphrase' => "A close restatement of the named work's point, not its exact words.",
    'editorial_summary' => "The app editors' summary of the cited sources.",
    'ai_assisted' => "Drafted with AI help, then checked against the cited sources and approved by a reviewer. It is not a scholar's words.",
];
$cmsCard = function (array $it) use ($cats, $app) {
    $c = $it['citation'] ?? [];
    $parts = array_filter([
        $it['_scholar']['name'] ?? null, $it['_source']['title'] ?? null,
        isset($c['edition']) ? 'ed. ' . $c['edition'] : null, isset($c['volume']) ? 'vol. ' . $c['volume'] : null,
        isset($c['page']) ? 'p. ' . $c['page'] : null,
        $app->surahName($it['surah']) . " {$it['surah']}:{$it['start_ayah']}" . ($it['end_ayah'] !== $it['start_ayah'] ? "–{$it['end_ayah']}" : ''),
    ]);
    $link = $c['url'] ?? ($it['_source']['url'] ?? null);
    ob_start(); ?>
    <div class="card stack">
      <div><span class="tag <?= $it['category'] === 'ai_assisted' ? 'ai' : 'accent' ?>"><?= h($cats[$it['category']] ?? $it['category']) ?></span> <span class="tag ok">Reviewed &amp; approved</span></div>
      <?php if (!empty($it['title'])): ?><h3><?= h($it['title']) ?></h3><?php endif; ?>
      <?php foreach (preg_split('/\n\s*\n/', (string)$it['body']) as $para): ?><p class="translation" style="font-size:17px<?= $it['category'] === 'direct_quotation' ? ';font-style:italic' : '' ?>"><?= nl2br(h(trim($para))) ?></p><?php endforeach; ?>
      <p class="faint">Source: <?= h(implode(' · ', $parts)) ?><?php if (!empty($it['reviewer'])): ?><br>Reviewed by <?= h($it['reviewer']) ?><?php endif; ?></p>
      <?php if ($link && str_starts_with($link, 'https://')): ?><a href="<?= h($link) ?>" rel="noopener noreferrer" target="_blank">Source link ↗</a><?php endif; ?>
    </div>
    <?php return ob_get_clean();
};
?>
<div class="row">
  <a class="iconbtn" href="/" aria-label="Back to today"><?= qj_icon('back') ?></a>
  <h3 class="grow" style="font-family:Inter,sans-serif;font-weight:600;font-size:17px"><?= h($app->studyTitle($study)) ?></h3>
  <form method="post" action="<?= h($url) ?>"><input type="hidden" name="_csrf" value="<?= $csrf ?>"><input type="hidden" name="tab" value="<?= h($tab) ?>">
    <?php $saved = $app->store->hasBookmark($p, 'study', $study['start'], $study['end']); ?>
    <button class="iconbtn <?= $saved ? 'on' : '' ?>" name="action" value="bookmark_study" aria-label="<?= $saved ? 'Remove saved study' : 'Save study' ?>" title="<?= $saved ? 'Saved' : 'Save study' ?>"><?= qj_icon('bookmark') ?></button>
  </form>
</div>
<nav class="tabs" aria-label="Study sections">
  <?php foreach (['read' => 'Read', 'words' => 'Words', 'context' => 'Context', 'tafsir' => 'Tafsir', 'reflect' => 'Reflect'] as $k => $label): ?>
    <a href="<?= h($url) ?>?tab=<?= $k ?>" class="<?= $tab === $k ? 'active' : '' ?>"<?= $tab === $k ? ' aria-current="page"' : '' ?>><?= $label ?></a>
  <?php endforeach; ?>
</nav>

<?php if (isset($_GET['done'])): $n = $app->progress->next(); ?>
<div class="card stack" style="margin-top:18px;text-align:center">
  <h2>Study complete</h2>
  <p class="muted"><?= $n ? 'May these verses stay with you. Up next: ' . h($app->studyTitle($n)) . '.' : 'You have reached the end of the Quran. Alhamdulillah.' ?></p>
  <div class="row" style="justify-content:center;flex-wrap:wrap"><a class="btn" href="/">Back to today</a><?php if ($n): ?><a class="btn ghost" href="<?= h(App::studyUrl($n)) ?>">Read the next study now</a><?php endif; ?></div>
</div>
<?php endif; ?>

<?php if ($tab === 'read'): ?>
  <div class="row" style="margin-top:22px;align-items:flex-end">
    <div class="grow"><h2><?= h($surah['name_translit']) ?></h2><p class="faint"><?= h($surah['name_en']) ?> · <?= h($surah['revelation_type']) ?> · <?= $surah['ayah_count'] ?> verses</p></div>
    <span class="arabic" style="font-size:28px;color:var(--ink-soft)"><?= h($surah['name_ar']) ?></span>
  </div>
  <?php if (!empty($verses[0]['bismillah'])): ?><p class="quran" style="text-align:center;color:var(--ink-soft);margin-top:16px"><?= h($verses[0]['bismillah']) ?></p><?php endif; ?>
  <div id="verses" data-reciter="<?= h($app->settings['reciter']) ?>">
  <?php foreach ($verses as $v): $vid = (int)$v['id']; $vs = $app->store->hasBookmark($p, 'verse', $vid, $vid); ?>
    <article class="verse" id="v<?= $vid ?>" data-surah="<?= $v['surah'] ?>" data-ayah="<?= $v['ayah'] ?>">
      <div class="tools">
        <span class="tag accent"><?= $v['surah'] ?>:<?= $v['ayah'] ?></span>
        <?php if ($v['sajdah']): ?><span class="tag">Sajdah (<?= h($v['sajdah']) ?>)</span><?php endif; ?>
        <span class="grow"></span>
        <button class="iconbtn js-play" type="button" aria-label="Play recitation of <?= $v['surah'] ?>:<?= $v['ayah'] ?>"><?= qj_icon('play') ?></button>
        <form method="post" action="<?= h($url) ?>"><input type="hidden" name="_csrf" value="<?= $csrf ?>"><input type="hidden" name="verse" value="<?= $vid ?>">
          <button class="iconbtn <?= $vs ? 'on' : '' ?>" name="action" value="bookmark_verse" aria-label="<?= $vs ? 'Remove saved verse' : 'Save verse' ?>"><?= qj_icon('bookmark') ?></button></form>
      </div>
      <p class="quran" lang="ar"><?= h($v['text_uthmani']) ?> <span class="mark"><?= App::ayahMark((int)$v['ayah']) ?></span></p>
      <?php if ($app->settings['transliteration']): ?><p class="translit"><?= App::translit($tl[$vid] ?? '') ?></p><?php endif; ?>
      <p class="translation"><?= h($texts[$vid] ?? '') ?></p>
    </article>
  <?php endforeach; ?>
  </div>
  <p class="faint" style="margin-top:16px">Arabic: Tanzil Uthmani text <?= h($q->meta['tanzil_version'] ?? '') ?> (verbatim, tanzil.net). Translation: <?= h($tr['translator']) ?> (<?= h($tr['name']) ?>). Transliteration: Tanzil. Recitation: <?= h(App::RECITERS[$app->settings['reciter']] ?? '') ?>, EveryAyah.com.</p>

<?php elseif ($tab === 'words'): ?>
  <div class="notice" style="margin-top:18px">Roots, lemmas and grammatical tags come from the Quranic Arabic Corpus (v0.4, University of Leeds). Word meanings are Quran.com's word-by-word glosses, which are literal aids, not a translation. Syntactic roles (iʿrāb) and contextual meanings are not included yet, because no reviewed source for them is available.</div>
  <?php foreach ($verses as $v):
      $words = $q->words((int)$v['id']);
      $gl = $online ? $app->online->glosses((int)$v['surah'], (int)$v['ayah']) : null;
      $byPos = ($gl && count($gl) === count($words)) ? array_column($gl, null, 'p') : [];
  ?>
    <div class="section"><span class="label">Verse <?= $v['surah'] ?>:<?= $v['ayah'] ?></span><?php if (!$byPos): ?><span class="faint"><?= $online ? 'Meanings unavailable offline' : 'Online meanings off' ?></span><?php endif; ?></div>
    <div class="stack">
    <?php foreach ($words as $w): $g = $byPos[(int)$w['position']] ?? null; $ar = $w['text_uthmani'] ?? Morphology::bw(implode('', array_column($w['segments'], 0))); ?>
      <div class="card word" style="padding:16px">
        <div class="grow">
          <p class="translation" style="font-size:17.5px;font-weight:500"><?= h($g['t'] ?? '—') ?></p>
          <?php if ($g && $g['tr'] !== ''): ?><p class="translit" style="font-size:13.5px"><?= h($g['tr']) ?></p><?php endif; ?>
          <div style="margin-top:6px"><span class="tag"><?= h(Morphology::POS[$w['pos']] ?? ($w['pos'] ?? '—')) ?></span>
          <?php if ($w['root_ar']): ?> <span class="tag accent">Root <span class="arabic" style="font-size:14px;font-weight:700"><?= h($w['root_ar']) ?></span></span><?php endif; ?></div>
          <details>
            <summary>Details</summary>
            <?php if ($w['lemma_ar']): ?><div class="kv"><span>Lemma (dictionary form)</span><span class="arabic" style="font-size:18px"><?= h($w['lemma_ar']) ?></span></div><?php endif; ?>
            <?php if ($w['root_ar']): ?><div class="kv"><span>Root letters</span><span class="arabic" style="font-size:18px"><?= h($w['root_ar']) ?></span></div>
            <div class="kv"><span>Occurrences of this root</span><span><?= number_format($q->rootCount($w['root_bw'])) ?> words (corpus count)</span></div><?php endif; ?>
            <p class="label" style="margin-top:8px">Morphology</p>
            <?php foreach ($w['segments'] as $seg): ?>
              <div class="seg"><span class="arabic"><?= h(Morphology::bw($seg[0])) ?></span><span><?= h(Morphology::describe($seg)) ?><br><span class="faint">Corpus tags: <?= h($seg[1] . ' | ' . $seg[2]) ?></span></span></div>
            <?php endforeach; ?>
            <?php if ($w['text_uthmani'] === null): ?><p class="faint">The corpus segments this verse differently from the Tanzil text; the word shown is the corpus form.</p><?php endif; ?>
          </details>
        </div>
        <span class="ar"><?= h($ar) ?></span>
      </div>
    <?php endforeach; ?>
    </div>
  <?php endforeach; ?>

<?php elseif ($tab === 'context'):
    $inSurah = array_values(array_filter($app->plan->studies, fn($s) => $s['surah'] === $study['surah']));
    $pos = array_search($study['index'], array_column($inSurah, 'index'), true) + 1;
    $prev = $study['index'] > 0 ? $app->plan->studies[$study['index'] - 1] : null;
    $next = $app->plan->studies[$study['index'] + 1] ?? null;
    $ctx = array_filter($cms, fn($i) => $i['type'] === 'context');
    $intro = array_filter($cms, fn($i) => $i['type'] === 'surah_intro');
    $neighbour = function (string $label, int $vid) use ($app, $q) {
        $v = $q->verses($vid, $vid)[0];
        $t = $q->text((int)$app->translation()['id'], $vid, $vid)[$vid] ?? '';
        return '<p class="label" style="margin-top:14px">' . h($label) . ' · ' . h($app->surahName((int)$v['surah'])) . " {$v['surah']}:{$v['ayah']}</p><p class=\"translation\" style=\"font-size:16.5px;font-style:italic;color:var(--ink-soft)\">" . h($t) . '</p>';
    };
?>
  <div class="section"><span class="label">About this surah</span></div>
  <div class="card">
    <div class="row"><h3 class="grow"><?= h($surah['name_translit']) ?> — <?= h($surah['name_en']) ?></h3><span class="arabic" style="font-size:22px;color:var(--ink-soft)"><?= h($surah['name_ar']) ?></span></div>
    <div style="margin-top:10px">
      <div class="kv"><span>Surah</span><span><?= $surah['number'] ?> of 114</span></div>
      <div class="kv"><span>Classification</span><span><?= h($surah['revelation_type']) ?></span></div>
      <div class="kv"><span>Traditional order of revelation</span><span><?= $surah['revelation_order'] ?></span></div>
      <div class="kv"><span>Verses</span><span><?= $surah['ayah_count'] ?></span></div>
      <div class="kv"><span>Sections (rukūʿ)</span><span><?= $surah['rukus'] ?></span></div>
      <div class="kv"><span>These verses</span><span>Juz <?= $verses[0]['juz'] ?> · Madinah mushaf page <?= $verses[0]['page'] ?></span></div>
    </div>
    <p class="faint" style="margin-top:8px">Source: Tanzil Quran metadata. Scholars differ on the Meccan/Medinan classification and the revelation order of some surahs; these values follow Tanzil's commonly used tables.</p>
  </div>
  <?php foreach ($intro as $it): ?><div style="margin-top:12px"><?= $cmsCard($it) ?></div><?php endforeach; ?>
  <div class="section"><span class="label">Where these verses sit</span></div>
  <div class="card">
    <h3 style="font-family:Inter,sans-serif;font-size:15px;font-weight:600">Verses <?= $study['start_ayah'] ?>–<?= $study['end_ayah'] ?> of <?= $surah['ayah_count'] ?> · study <?= $pos ?> of <?= count($inSurah) ?> in this surah</h3>
    <?php if ($study['rationale']): ?><p class="muted" style="margin-top:8px">Grouping note: <?= h($study['rationale']) ?></p><?php endif; ?>
    <?php if ($prev) echo $neighbour('Before this passage', $prev['end']); ?>
    <?php if ($next) echo $neighbour('After this passage', $next['start']); ?>
    <p class="faint" style="margin-top:10px">Neighbouring verses are quoted from the translation for continuity.</p>
  </div>
  <div class="section"><span class="label">Historical context</span></div>
  <?php if (!$ctx): ?>
    <div class="card"><p class="muted">No reviewed historical context or occasion of revelation has been published for these verses yet. This app does not generate them: they are added only after source verification and review.</p></div>
  <?php else: foreach ($ctx as $it): ?><div style="margin-top:12px"><?= $cmsCard($it) ?></div><?php endforeach; endif; ?>

<?php elseif ($tab === 'tafsir'):
    $selV = (int)($_GET['v'] ?? $verses[0]['id']);
    if ($selV < $study['start'] || $selV > $study['end']) { $selV = (int)$verses[0]['id']; }
    $sel = $verses[$selV - $study['start']];
    $work = (int)($_GET['work'] ?? 0);
    $taf = array_filter($cms, fn($i) => $i['type'] === 'tafsir');
?>
  <div class="section"><span class="label">Reviewed tafsir notes</span></div>
  <?php if (!$taf): ?>
    <div class="card"><p class="muted">No reviewed English tafsir summary has been published for these verses yet. Below you can read the original Arabic text of classical tafsir works, and links to recognised English tafsir.</p></div>
  <?php else: foreach ($taf as $it): ?><div style="margin-top:12px"><?= $cmsCard($it) ?></div><?php endforeach; endif; ?>
  <div class="section"><span class="label">Classical tafsir · original Arabic</span></div>
  <div class="chips">
    <?php foreach ($verses as $v): ?><a href="<?= h($url) ?>?tab=tafsir&amp;v=<?= $v['id'] ?><?= $work ? "&amp;work=$work" : '' ?>" class="<?= (int)$v['id'] === $selV ? 'active' : '' ?>"><?= $v['surah'] ?>:<?= $v['ayah'] ?></a><?php endforeach; ?>
  </div>
  <div class="stack" style="margin-top:12px">
  <?php foreach (Online::TAFSIRS as $id => [$name, $nameAr, $ah, $ce, $title]): $open = $work === $id; ?>
    <div class="card" id="t<?= $id ?>">
      <a class="row" style="color:inherit" href="<?= h($url) ?>?tab=tafsir&amp;v=<?= $selV ?><?= $open ? '' : "&amp;work=$id" ?>#t<?= $id ?>">
        <span class="grow"><strong><?= h($name) ?></strong><br><span class="faint"><?= h($title) ?> · d. <?= $ah ?> AH / <?= $ce ?> CE</span></span>
        <span class="arabic" style="font-size:19px;color:var(--ink-soft)"><?= h($nameAr) ?></span>
      </a>
      <?php if ($open): $t = $online ? $app->online->tafsir($id, (int)$sel['surah'], (int)$sel['ayah']) : null; ?>
        <?php if (!$t): ?>
          <p class="faint" style="margin-top:12px"><?= $online ? 'This text could not be loaded right now. Please try again later.' : 'Online sources are turned off in your settings.' ?></p>
        <?php else: ?>
          <div style="margin-top:12px"><span class="tag accent">Direct quotation</span> <span class="tag">Arabic original</span><?php if (count($t['keys']) > 1): ?> <span class="tag">Covers <?= h($t['keys'][0] . '–' . explode(':', end($t['keys']))[1]) ?></span><?php endif; ?></div>
          <div class="tafsir-text" lang="ar" style="margin-top:12px"><?php foreach ($t['paragraphs'] as $para): ?><p><?= h($para) ?></p><?php endforeach; ?></div>
          <p class="faint" style="margin-top:10px"><?= h("$name, $title") ?>. Original text shown word for word from the Quran.com digital edition, with nothing translated or summarised. The digital source does not give volume and page numbers.</p>
          <a href="<?= h($t['url']) ?>" target="_blank" rel="noopener noreferrer">View source ↗</a>
        <?php endif; ?>
      <?php endif; ?>
    </div>
  <?php endforeach; ?>
  </div>
  <div class="section"><span class="label">English tafsir · external</span></div>
  <div class="list">
    <?php $s = (int)$sel['surah']; $a = (int)$sel['ayah']; foreach ([
        ['Ibn Kathir (abridged English, Darussalam) – on Quran.com', "https://quran.com/$s:$a/tafsirs/en-tafisr-ibn-kathir"],
        ["Ma'arif al-Qur'an (Mufti Muhammad Shafi) – on Quran.com", "https://quran.com/$s:$a/tafsirs/en-tafsir-maarif-ul-quran"],
        ['Tafsir al-Jalalayn (English, Royal Aal al-Bayt Institute) – altafsir.com', "https://www.altafsir.com/Tafasir.asp?tMadhNo=0&tTafsirNo=74&tSoraNo=$s&tAyahNo=$a&tDisplay=yes&LanguageID=2"],
    ] as [$label, $href]): ?>
      <a href="<?= h($href) ?>" target="_blank" rel="noopener noreferrer"><span class="grow"><?= h($label) ?></span><span class="chev">↗</span></a>
    <?php endforeach; ?>
  </div>
  <p class="faint" style="margin-top:10px">These English works are under copyright, so the app links to their publishers' sites and does not copy them.</p>
  <div class="section"><span class="label">How content is labelled</span></div>
  <div class="stack"><?php foreach ($cats as $k => $label): ?><div class="row" style="align-items:flex-start"><span class="tag <?= $k === 'ai_assisted' ? 'ai' : 'accent' ?>"><?= h($label) ?></span><span class="faint grow"><?= h($catHelp[$k]) ?></span></div><?php endforeach; ?></div>

<?php else: /* reflect */
    $prompts = [
        'Which word or phrase in these verses stayed with you, and why?', 'What do these verses tell you about Allah?',
        'Is there one thing you could carry from these verses into today?', 'How might these verses shape the way you treat the people around you?',
        'What question would you like to learn more about from these verses?', 'Read the verses again slowly. What did you notice the second time?',
        'Is there a du‘a (supplication) these verses inspire you to make?', 'What feeling did these verses leave you with?',
    ];
    $refl = array_filter($cms, fn($i) => $i['type'] === 'reflection');
    $notes = $app->store->notes($p, $study['start'], $study['end']);
    $editId = (int)($_GET['edit'] ?? 0);
?>
  <?php if ($refl): ?><div class="section"><span class="label">Reflections on these verses</span></div><?php foreach ($refl as $it): ?><div style="margin-top:12px"><?= $cmsCard($it) ?></div><?php endforeach; endif; ?>
  <div class="section"><span class="label">Questions to sit with</span></div>
  <div class="card stack">
    <?php for ($i = 0; $i < 3; $i++): ?><p class="prompt"><?= h($prompts[($study['index'] + $i * 3) % count($prompts)]) ?></p><?php endfor; ?>
    <p class="faint">General reflection prompts written by the app's editors. They are not tafsir and make no claim about the meaning of these verses.</p>
  </div>
  <div class="section" id="notes"><span class="label">Your reflections</span></div>
  <div class="stack">
    <?php foreach ($notes as $n): ?>
      <div class="card">
        <?php if ($editId === (int)$n['id']): ?>
          <form method="post" action="<?= h($url) ?>" class="stack"><input type="hidden" name="_csrf" value="<?= $csrf ?>"><input type="hidden" name="id" value="<?= (int)$n['id'] ?>">
            <label class="sr-only" for="note-<?= (int)$n['id'] ?>">Edit reflection</label>
            <textarea id="note-<?= (int)$n['id'] ?>" name="text" maxlength="20000" required><?= h($n['text']) ?></textarea>
            <div class="row"><button class="btn" name="action" value="note_save">Save</button><a class="btn ghost" href="<?= h($url) ?>?tab=reflect#notes">Cancel</a><span class="grow"></span>
            <button class="btn link" name="action" value="note_delete" data-confirm="Delete this reflection? This cannot be undone.">Delete</button></div>
          </form>
        <?php else: ?>
          <p class="note"><?= h($n['text']) ?></p>
          <div class="row" style="margin-top:8px"><span class="faint grow"><?= h(date('j M Y', (int)$n['updated_at'])) ?></span><a href="<?= h($url) ?>?tab=reflect&amp;edit=<?= (int)$n['id'] ?>#notes">Edit</a></div>
        <?php endif; ?>
      </div>
    <?php endforeach; ?>
    <form method="post" action="<?= h($url) ?>" class="card stack"><input type="hidden" name="_csrf" value="<?= $csrf ?>">
      <label for="new-note" class="label"><?= $notes ? 'Add another reflection' : 'Write a reflection' ?></label>
      <textarea id="new-note" name="text" maxlength="20000" placeholder="What did these verses bring to mind?" required></textarea>
      <div class="row"><button class="btn" name="action" value="note_save">Save reflection</button><span class="faint grow">Private to you.</span></div>
    </form>
  </div>
<?php endif; ?>

<div class="study-bar">
  <button class="iconbtn play js-toggle" type="button" aria-label="Play recitation"><svg viewBox="0 0 24 24" aria-hidden="true"><path class="js-icon" d="M8 5.5v13l11-6.5z"/></svg></button>
  <button class="iconbtn js-prev" type="button" aria-label="Previous verse"><?= qj_icon('prev') ?></button>
  <button class="iconbtn js-next" type="button" aria-label="Next verse"><?= qj_icon('next') ?></button>
  <button class="iconbtn js-replay" type="button" aria-label="Replay verse"><?= qj_icon('replay') ?></button>
  <span class="grow"></span>
  <?php if ($done): ?>
    <span class="state-done" style="padding:0 10px">✓ Studied</span>
  <?php else: ?>
    <form method="post" action="<?= h($url) ?>"><input type="hidden" name="_csrf" value="<?= $csrf ?>"><button class="btn" name="action" value="complete">Complete</button></form>
  <?php endif; ?>
</div>
<script type="application/json" id="study-audio"><?= json_encode(['reciter' => $app->settings['reciter'], 'verses' => array_map(fn($v) => ['id' => (int)$v['id'], 's' => (int)$v['surah'], 'a' => (int)$v['ayah']], $verses)], JSON_HEX_TAG | JSON_HEX_AMP) ?></script>
