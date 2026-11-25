<?php
declare(strict_types=1);

/**
 * Test suite for the PHP web app. No dependencies: `php tests/run.php`
 * Unit tests + end-to-end HTTP tests against a throwaway `php -S` server.
 */

use QJ\{App, Plan, Progress, Quran, Morphology, Online};

require_once dirname(__DIR__) . '/src/App.php';

$pass = 0;
$fail = 0;
function test(string $name, callable $fn): void
{
    global $pass, $fail;
    try {
        $fn();
        $pass++;
        echo "  ✓ $name\n";
    } catch (Throwable $e) {
        $fail++;
        echo "  ✗ $name\n      " . $e->getMessage() . "\n";
    }
}
function eq($a, $b, string $msg = ''): void
{
    if ($a !== $b) {
        throw new RuntimeException(($msg ? "$msg: " : '') . 'expected ' . var_export($b, true) . ', got ' . var_export($a, true));
    }
}
function ok($cond, string $msg): void
{
    if (!$cond) {
        throw new RuntimeException($msg);
    }
}

$root = dirname(__DIR__, 2);
$quran = new Quran($root . '/app/assets/db/quran.db');
$overrides = json_decode(file_get_contents($root . '/app/assets/content/groupings.json'), true)['groupings'];

echo "Unit\n";

// Fingerprints produced by the Flutter implementation (app/lib/domain/grouping.dart).
$dart = [
    1 => [6236, '7f4dd552ca64437cf8d34990eb6da96c96da1a2f2b30b87a8bb6bdf768d5b3ee'],
    2 => [3119, 'b1f03349966ac522862e85d337ad3f6c9eecb09f01a245e6995a00d06ed4724a'],
    3 => [2162, 'e7fbdf8dc03c546617a1f74c55fe7d5d28c1473ca66049faf9d4da48c963edb8'],
    5 => [1532, '16676ac7347f8362651f849235bfd7ba941e3cda357345c50f2601cc06a3196d'],
];
foreach ($dart as $n => [$count, $hash]) {
    test("study plan ($n verses/study) is identical to the mobile app's", function () use ($quran, $overrides, $n, $count, $hash) {
        $p = new Plan($quran->surahs, $quran->wordCounts, $n === 3 ? $overrides : [], $n);
        eq($p->count(), $count, 'study count');
        eq(hash('sha256', implode(',', array_map(fn($s) => "{$s['start']}-{$s['end']}", $p->studies))), $hash, 'plan fingerprint');
    });
}

$plan = new Plan($quran->surahs, $quran->wordCounts, $overrides);
$c = fn(int $a, int $b, string $at) => ['start_id' => $a, 'end_id' => $b, 'completed_at' => strtotime($at . ' UTC') * 1000];
$sessions = App::defaults()['sessions'];

test('Al-Fatihah grouping and 2:282 alone', function () use ($plan, $quran) {
    eq(Plan::refLabel($plan->studies[0]), '1:1–4');
    eq(Plan::refLabel($plan->studies[1]), '1:5–7');
    $id = $quran->surah(2)['first_verse_id'] + 281;
    $s = $plan->forVerse($id);
    eq([$s['start'], $s['end']], [$id, $id]);
    eq(Plan::refLabel(end($plan->studies)), '114:4–6');
});

test('missed days never skip verses; today continues from the frontier', function () use ($plan, $c, $sessions) {
    $p = new Progress($plan, [$c(1, 4, '2026-03-01 08:00')]);
    $slots = $p->today($sessions, new DateTimeImmutable('2026-03-09 20:30', new DateTimeZone('UTC')));
    eq(array_map(fn($s) => $s['study']['index'], $slots), [1, 2, 3]);
    eq(array_map(fn($s) => $s['state'], $slots), ['ready', 'ready', 'ready']);
});

test('today slots: done, ready and upcoming by local time', function () use ($plan, $c, $sessions) {
    $p = new Progress($plan, [$c(1, 4, '2026-03-02 07:10')]);
    $slots = $p->today($sessions, new DateTimeImmutable('2026-03-02 14:00', new DateTimeZone('UTC')));
    eq(array_map(fn($s) => $s['state'], $slots), ['done', 'ready', 'upcoming']);
});

test('time zone decides which day a completion belongs to', function () use ($plan, $c, $sessions) {
    // 23:30 UTC on the 2nd is already the 3rd in Tokyo.
    $p = new Progress($plan, [$c(1, 4, '2026-03-02 23:30')]);
    eq(count($p->completedOn(new DateTimeImmutable('2026-03-03 10:00', new DateTimeZone('Asia/Tokyo')))), 1);
    eq(count($p->completedOn(new DateTimeImmutable('2026-03-03 10:00', new DateTimeZone('UTC')))), 0);
});

test('reading ahead, re-reading and completion of the whole Quran', function () use ($plan, $c) {
    $p = new Progress($plan, [$c($plan->studies[3]['start'], $plan->studies[3]['end'], '2026-01-01'), $c(1, 4, '2026-01-01'), $c(1, 4, '2026-01-02')]);
    eq($p->next()['index'], 1);
    eq($p->completedVerses(), 4 + ($plan->studies[3]['end'] - $plan->studies[3]['start'] + 1));
    $all = new Progress($plan, [$c(1, 6236, '2026-01-01')]);
    eq($all->next(), null);
    eq($all->fraction(), 1.0);
});

test('search: reference, Arabic in both spellings, English, LIKE wildcards are literal', function () use ($quran) {
    eq($quran->search('2:255', 1), [262]);
    ok(in_array(2, $quran->search('الحمد لله رب العالمين', 1), true), 'everyday spelling should match 1:2');
    eq($quran->search('Lord of the Worlds', 1)[0], 2);
    eq($quran->search('%', 1), []);
    eq($quran->search('zzzqqq', 1), []);
});

test('morphology expansions and Buckwalter decoding', function () {
    eq(Morphology::describe(['Hamodu', 'N', 'STEM|POS:N|LEM:Hamod|ROOT:Hmd|M|NOM']), 'Noun · masculine · nominative');
    eq(Morphology::describe(['{lo', 'DET', 'PREFIX|Al+']), 'Prefix: definite article al-');
    eq(Morphology::describe(['hum', 'PRON', 'SUFFIX|PRON:3MP']), 'Suffix: attached pronoun (3rd person masculine plural)');
    eq(Morphology::bw('Hamod'), 'حَمْد');
    eq(Morphology::bw('maE2'), 'مَع');
});

test('transliteration markup is rendered safely', function () {
    eq(App::translit('Al<u>h</u>amdu<b>a</b>'), 'Al<span class="long">h</span>amdu<span class="silent">a</span>');
    ok(!str_contains(App::translit('<script>alert(1)</script>'), '<script>'), 'script tags must be escaped');
});

test('tafsir HTML keeps words, removes tags', function () {
    eq(Online::htmlToParagraphs('<p lang="ar">قال <span class="blue">ابن</span> كثير</p><p>ثانٍ &amp; ثالث</p>'), ['قال ابن كثير', 'ثانٍ & ثالث']);
});

// ------------------------------------------------------------------ HTTP
echo "HTTP (end to end)\n";
$port = 18000 + random_int(0, 999);
$tmp = sys_get_temp_dir() . '/qjweb-' . bin2hex(random_bytes(4));
mkdir($tmp);
$cmd = sprintf('QJ_WEB_DB=%s php -S 127.0.0.1:%d -t %s %s > %s 2>&1 & echo $!',
    escapeshellarg("$tmp/web.sqlite"), $port, escapeshellarg(dirname(__DIR__) . '/public'),
    escapeshellarg(dirname(__DIR__) . '/public/index.php'), escapeshellarg("$tmp/server.log"));
$pid = (int)shell_exec($cmd);
register_shutdown_function(fn() => shell_exec("kill $pid 2>/dev/null; rm -rf " . escapeshellarg($tmp)));
for ($i = 0; $i < 50 && @file_get_contents("http://127.0.0.1:$port/healthz") !== 'ok'; $i++) {
    usleep(100000);
}

final class Browser
{
    public array $cookies = [];
    public array $headers = [];
    public int $status = 0;
    public function __construct(private int $port) {}
    public function req(string $method, string $path, array $form = []): string
    {
        $h = ['Cookie: ' . implode('; ', array_map(fn($k, $v) => "$k=$v", array_keys($this->cookies), $this->cookies))];
        $opts = ['method' => $method, 'ignore_errors' => true, 'follow_location' => 0, 'header' => $h];
        if ($method === 'POST') {
            $opts['header'][] = 'Content-Type: application/x-www-form-urlencoded';
            $opts['content'] = http_build_query($form);
        }
        $body = file_get_contents("http://127.0.0.1:{$this->port}$path", false, stream_context_create(['http' => $opts]));
        $this->headers = $http_response_header;
        preg_match('#^HTTP/\S+ (\d+)#', $this->headers[0], $m);
        $this->status = (int)$m[1];
        foreach ($this->headers as $line) {
            if (preg_match('/^Set-Cookie: ([^=]+)=([^;]*)/i', $line, $m)) {
                if ($m[2] === '' || $m[2] === 'deleted') { unset($this->cookies[$m[1]]); } else { $this->cookies[$m[1]] = $m[2]; }
            }
        }
        return (string)$body;
    }
    public function location(): ?string
    {
        foreach ($this->headers as $l) { if (stripos($l, 'Location:') === 0) { return trim(substr($l, 9)); } }
        return null;
    }
    public function csrf(string $html): string
    {
        preg_match('/name="_csrf" value="([a-f0-9]+)"/', $html, $m);
        return $m[1] ?? '';
    }
}

$b = new Browser($port);

test('first visit creates a private profile and goes to onboarding', function () use ($b) {
    $b->req('GET', '/');
    eq($b->status, 303);
    eq($b->location(), '/welcome');
    ok(isset($b->cookies['qj_token']) && strlen($b->cookies['qj_token']) === 48, 'token cookie');
    $cookieLine = implode("\n", array_filter($b->headers, fn($l) => stripos($l, 'Set-Cookie: qj_token') === 0));
    ok(stripos($cookieLine, 'HttpOnly') !== false && stripos($cookieLine, 'SameSite=Lax') !== false, 'cookie flags');
});

test('security headers present', function () use ($b) {
    $b->req('GET', '/welcome');
    $all = implode("\n", $b->headers);
    ok(str_contains($all, "Content-Security-Policy: default-src 'self'"), 'CSP');
    ok(str_contains($all, "frame-ancestors 'none'"), 'frame-ancestors');
    ok(str_contains($all, 'X-Content-Type-Options: nosniff'), 'nosniff');
});

test('POST without CSRF token is rejected', function () use ($b) {
    $b->req('POST', '/welcome?step=2', ['time_morning' => '05:00']);
    eq($b->status, 403);
});

test('onboarding saves schedule and preferences, then starts at Al-Fatihah', function () use ($b) {
    $t = $b->csrf($b->req('GET', '/welcome?step=2'));
    $b->req('POST', '/welcome?step=2', ['_csrf' => $t, 'time_morning' => '06:15', 'on_morning' => '1', 'time_afternoon' => '13:00', 'time_evening' => '21:00', 'on_evening' => '1']);
    eq($b->location(), '/welcome?step=3');
    $b->req('POST', '/welcome?step=3', ['_csrf' => $t, 'translation_id' => '2', 'transliteration' => '1', 'arabic_scale' => '1.4', 'theme' => 'dark']);
    $b->req('POST', '/welcome?step=4', ['_csrf' => $t]);
    eq($b->location(), '/');
    $home = $b->req('GET', '/');
    eq($b->status, 200);
    ok(str_contains($home, 'Your journey begins'), 'hero');
    ok(str_contains($home, 'Al-Faatiha'), 'Al-Fatihah first');
    ok(substr_count($home, 'class="state-') === 2, 'two enabled sessions (afternoon off)');
    ok(str_contains($home, 'data-theme="dark"') && str_contains($home, 'scale-14'), 'theme and Arabic size applied');
});

test('study page renders the verbatim Arabic, translation and transliteration', function () use ($b, $quran) {
    $html = $b->req('GET', '/study/1-4');
    eq($b->status, 200);
    foreach ($quran->verses(1, 4) as $v) {
        ok(str_contains($html, htmlspecialchars($v['text_uthmani'])), "verse {$v['id']} verbatim");
    }
    ok(str_contains($html, 'Most Gracious, Most Merciful'), 'Yusuf Ali chosen at onboarding');
    ok(str_contains($html, 'class="translit"'), 'transliteration shown');
    ok(!str_contains($html, '1:5</span>'), 'only this study\'s verses');
});

test('non-canonical study URLs redirect to the real study', function () use ($b) {
    $b->req('GET', '/study/2-3');
    eq($b->location(), '/study/1-4');
});

test('all study tabs render (offline sources) and Words shows corpus roots', function () use ($b) {
    $t = $b->csrf($b->req('GET', '/settings'));
    $b->req('POST', '/settings', ['_csrf' => $t, 'action' => 'reading', 'translation_id' => '2', 'transliteration' => '1', 'arabic_scale' => '1.4', 'reciter' => 'Husary_128kbps', 'verses_per_study' => '3', 'theme' => 'dark']); // online off
    foreach (['words' => 'س م و', 'context' => 'does not generate them', 'tafsir' => 'Ibn Kathir', 'reflect' => 'not tafsir'] as $tab => $needle) {
        $html = $b->req('GET', "/study/1-4?tab=$tab");
        eq($b->status, 200, $tab);
        ok(str_contains($html, $needle), "$tab contains '$needle'");
    }
    $html = $b->req('GET', '/study/1-4?tab=tafsir&v=2&work=14');
    ok(str_contains($html, 'Online sources are turned off'), 'tafsir respects the online switch');
});

test('complete a study: progress, today and next study update', function () use ($b) {
    $t = $b->csrf($b->req('GET', '/study/1-4'));
    $b->req('POST', '/study/1-4', ['_csrf' => $t, 'action' => 'complete']);
    eq($b->location(), '/study/1-4?done=1');
    $html = $b->req('GET', '/study/1-4?done=1');
    ok(str_contains($html, 'Up next: Al-Faatiha 1:5–7'), 'up next');
    $home = $b->req('GET', '/');
    ok(str_contains($home, 'Your next study') && str_contains($home, 'Verses 5–7'), 'hero advanced');
    ok(str_contains($home, '4 of 6,236 verses'), 'progress');
});

test('bookmarks: verse and study toggle, appear in Saved, removable', function () use ($b) {
    $t = $b->csrf($b->req('GET', '/study/1-4'));
    $b->req('POST', '/study/1-4', ['_csrf' => $t, 'action' => 'bookmark_verse', 'verse' => '2']);
    $b->req('POST', '/study/1-4', ['_csrf' => $t, 'action' => 'bookmark_study']);
    $b->req('POST', '/study/1-4', ['_csrf' => $t, 'action' => 'bookmark_verse', 'verse' => '99']); // outside study: ignored
    $saved = $b->req('GET', '/saved?tab=verses');
    ok(str_contains($saved, 'Al-Faatiha 1:2'), 'verse saved');
    ok(!str_contains($saved, '1:99'), 'out-of-study verse ignored');
    ok(str_contains($b->req('GET', '/saved?tab=studies'), 'Al-Faatiha 1:1–4'), 'study saved');
    preg_match('/name="id" value="(\d+)"/', $saved, $m);
    $b->req('POST', '/saved', ['_csrf' => $t, 'action' => 'remove', 'id' => $m[1], 'tab' => 'verses']);
    ok(str_contains($b->req('GET', '/saved?tab=verses'), 'No saved verses yet'), 'removed');
});

test('reflections are saved, escaped (no XSS), editable and deletable', function () use ($b) {
    $t = $b->csrf($b->req('GET', '/study/1-4?tab=reflect'));
    $evil = 'Praise <script>alert(1)</script> & thanks';
    $b->req('POST', '/study/1-4', ['_csrf' => $t, 'action' => 'note_save', 'text' => $evil]);
    $html = $b->req('GET', '/study/1-4?tab=reflect');
    ok(str_contains($html, 'Praise &lt;script&gt;alert(1)&lt;/script&gt; &amp; thanks'), 'escaped');
    ok(!str_contains($html, '<script>alert(1)'), 'no raw script');
    preg_match('/edit=(\d+)/', $html, $m);
    $b->req('POST', '/study/1-4', ['_csrf' => $t, 'action' => 'note_save', 'id' => $m[1], 'text' => 'Edited reflection']);
    ok(str_contains($b->req('GET', '/saved?tab=reflections'), 'Edited reflection'), 'edited, in Saved');
    $b->req('POST', '/study/1-4', ['_csrf' => $t, 'action' => 'note_delete', 'id' => $m[1]]);
    ok(!str_contains($b->req('GET', '/study/1-4?tab=reflect'), 'Edited reflection'), 'deleted');
});

test('journey, surah, reader, library search and sources pages', function () use ($b) {
    ok(str_contains($b->req('GET', '/journey'), 'All 114 surahs'), 'journey');
    eq(substr_count($b->req('GET', '/journey'), 'href="/surah/'), 114);
    ok(str_contains($b->req('GET', '/surah/2'), 'Verses 1–3'), 'surah studies');
    ok(str_contains($b->req('GET', '/read/114'), 'id="a6"'), 'reader');
    ok(str_contains($b->req('GET', '/library?q=2%3A255'), 'Al-Baqara 2:255'), 'reference search');
    ok(str_contains($b->req('GET', '/library?q=' . urlencode('العالمين')), 'Al-Faatiha 1:2'), 'Arabic search');
    ok(str_contains($b->req('GET', '/sources'), 'Current plan: 2,162 studies'), 'methodology');
    $b->req('GET', '/surah/115');
    eq($b->status, 404);
});

test('calendar export: one daily event per enabled session, in the user time zone', function () use ($b) {
    $b->cookies['qj_tz'] = 'Europe/London';
    $b->req('GET', '/');
    $ics = $b->req('GET', '/calendar.ics');
    ok(str_contains(implode("\n", $b->headers), 'text/calendar'), 'content type');
    eq(substr_count($ics, 'BEGIN:VEVENT'), 2, 'afternoon disabled');
    ok(str_contains($ics, 'DTSTART;TZID=Europe/London:') && str_contains($ics, 'T061500'), 'morning 06:15 London');
    ok(str_contains($ics, 'RRULE:FREQ=DAILY') && str_contains($ics, 'BEGIN:VALARM'), 'daily with alarm');
});

test('export JSON contains the profile data', function () use ($b) {
    $j = json_decode($b->req('GET', '/export.json'), true);
    eq(count($j['completions']), 1);
    eq($j['completions'][0]['end_id'], 4);
    ok(!isset($j['completions'][0]['profile']), 'no internal ids');
});

test('transfer code restores on a second device', function () use ($b, $port) {
    preg_match('/data-code="([A-F0-9-]+)"/', $b->req('GET', '/settings'), $m);
    $other = new Browser($port);
    $other->req('GET', '/welcome');
    $t = $other->csrf($other->req('GET', '/welcome?step=4'));
    $other->req('POST', '/welcome?step=4', ['_csrf' => $t]);
    $t = $other->csrf($other->req('GET', '/settings'));
    $other->req('POST', '/settings', ['_csrf' => $t, 'action' => 'restore', 'code' => 'nonsense']);
    eq($other->location(), '/settings?err=code#device');
    $other->req('POST', '/settings', ['_csrf' => $t, 'action' => 'restore', 'code' => strtolower($m[1])]);
    eq($other->location(), '/?restored=1');
    ok(str_contains($other->req('GET', '/'), '4 of 6,236 verses'), 'same journey on the second device');
});

test('static files cannot escape the assets folder', function () use ($b) {
    $body = $b->req('GET', '/assets/../../src/App.php');
    ok(!str_contains($body, 'namespace QJ'), 'source must not be served');
});

test('erase deletes the profile', function () use ($b) {
    $t = $b->csrf($b->req('GET', '/settings'));
    $b->req('POST', '/settings', ['_csrf' => $t, 'action' => 'erase']);
    eq($b->location(), '/welcome');
    $b->req('GET', '/');
    eq($b->location(), '/welcome');
});

echo "\n$pass passed, $fail failed\n";
exit($fail ? 1 : 0);
