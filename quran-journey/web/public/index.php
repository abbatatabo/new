<?php
declare(strict_types=1);

use QJ\App;
use QJ\Plan;

require_once dirname(__DIR__) . '/src/App.php';

// Static files when running under `php -S` (production servers serve them directly).
if (PHP_SAPI === 'cli-server') {
    $file = __DIR__ . parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
    if ($file !== __DIR__ . '/' && is_file($file) && str_starts_with(realpath($file), __DIR__ . '/assets/')) {
        return false;
    }
}

App::securityHeaders();
$app = new App();
$app->boot();

$method = $_SERVER['REQUEST_METHOD'];
$path = rtrim(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '/', '/') ?: '/';
if ($method === 'POST') {
    $app->checkCsrf();
}
$post = fn(string $k, $d = null) => $_POST[$k] ?? $d;

// ------------------------------------------------------------------ routes
if ($path === '/healthz') {
    header('Content-Type: text/plain');
    echo 'ok';
    exit;
}

if ($path === '/welcome') {
    $step = max(1, min(4, (int)($_GET['step'] ?? 1)));
    if ($method === 'POST') {
        $s = &$app->settings;
        if ($step === 2) {
            foreach ($s['sessions'] as $i => $sess) {
                $t = (string)$post('time_' . $sess['id'], '');
                if (preg_match('/^([01]\d|2[0-3]):([0-5]\d)$/', $t, $m)) {
                    $s['sessions'][$i]['minutes'] = (int)$m[1] * 60 + (int)$m[2];
                }
                $s['sessions'][$i]['enabled'] = $post('on_' . $sess['id']) === '1';
            }
        } elseif ($step === 3) {
            $s['translation_id'] = in_array((int)$post('translation_id'), array_map(fn($t) => (int)$t['id'], $app->quran->englishTranslations()), true) ? (int)$post('translation_id') : 1;
            $s['transliteration'] = $post('transliteration') === '1';
            $s['arabic_scale'] = max(0.8, min(1.8, (float)$post('arabic_scale', 1)));
            $s['theme'] = in_array($post('theme'), ['system', 'light', 'dark'], true) ? $post('theme') : 'system';
        } elseif ($step === 4) {
            $s['onboarded'] = true;
            unset($s);
            $app->save();
            App::redirect('/');
        }
        unset($s);
        $app->save();
        App::redirect('/welcome?step=' . ($step + 1));
    }
    $app->render('welcome', ['step' => $step], 'Welcome', 'none');
    exit;
}

if (!$app->settings['onboarded'] && $method === 'GET' && !in_array($path, ['/sources', '/privacy'], true)) {
    App::redirect('/welcome');
}

if ($path === '/') {
    $app->render('today', [], 'Today', 'today');
    exit;
}

if (preg_match('#^/study/(\d+)-(\d+)$#', $path, $m)) {
    $study = $app->plan->byRange((int)$m[1], (int)$m[2]) ?? $app->plan->forVerse((int)$m[1]);
    if ($study['start'] !== (int)$m[1] || $study['end'] !== (int)$m[2]) {
        App::redirect(App::studyUrl($study));
    }
    $tab = in_array($_GET['tab'] ?? 'read', ['read', 'words', 'context', 'tafsir', 'reflect'], true) ? ($_GET['tab'] ?? 'read') : 'read';
    if ($method === 'POST') {
        $action = (string)$post('action');
        $p = $app->profile;
        $back = App::studyUrl($study) . '?tab=' . urlencode((string)$post('tab', $tab));
        switch ($action) {
            case 'complete':
                $app->store->addCompletion($p, $study['start'], $study['end'], (int)$app->settings['journey']);
                $app->rebuild();
                App::redirect(App::studyUrl($study) . '?done=1');
            case 'bookmark_study':
                $app->store->toggleBookmark($p, 'study', $study['start'], $study['end'], $app->studyTitle($study));
                App::redirect($back);
            case 'bookmark_verse':
                $v = (int)$post('verse');
                if ($v >= $study['start'] && $v <= $study['end']) {
                    $ayah = $study['start_ayah'] + ($v - $study['start']);
                    $app->store->toggleBookmark($p, 'verse', $v, $v, $app->surahName($study['surah']) . " {$study['surah']}:$ayah");
                }
                App::redirect($back . '#v' . $v);
            case 'note_save':
                $text = trim((string)$post('text', ''));
                if ($text !== '' && mb_strlen($text) <= 20000) {
                    $app->store->saveNote($p, ((int)$post('id')) ?: null, $study['start'], $study['end'], $text);
                }
                App::redirect(App::studyUrl($study) . '?tab=reflect#notes');
            case 'note_delete':
                $app->store->deleteNote($p, (int)$post('id'));
                App::redirect(App::studyUrl($study) . '?tab=reflect#notes');
        }
        App::redirect($back);
    }
    $app->render('study', ['study' => $study, 'tab' => $tab], $app->studyTitle($study), 'study');
    exit;
}

if ($path === '/next') {
    $n = $app->progress->next();
    App::redirect($n ? App::studyUrl($n) : '/');
}

if ($path === '/journey') {
    $app->render('journey', [], 'Journey', 'journey');
    exit;
}

if (preg_match('#^/surah/(\d{1,3})$#', $path, $m) && (int)$m[1] >= 1 && (int)$m[1] <= 114) {
    $app->render('surah', ['n' => (int)$m[1]], $app->surahName((int)$m[1]), 'journey');
    exit;
}

if ($path === '/library') {
    $app->render('library', ['q' => trim((string)($_GET['q'] ?? ''))], 'Library', 'library');
    exit;
}

if (preg_match('#^/read/(\d{1,3})$#', $path, $m) && (int)$m[1] >= 1 && (int)$m[1] <= 114) {
    $app->render('reader', ['n' => (int)$m[1], 'ayah' => (int)($_GET['a'] ?? 0)], $app->surahName((int)$m[1]), 'library');
    exit;
}

if ($path === '/saved') {
    if ($method === 'POST' && $post('action') === 'remove') {
        $app->store->db->prepare('DELETE FROM bookmarks WHERE id = ? AND profile = ?')->execute([(int)$post('id'), $app->profile]);
        App::redirect('/saved?tab=' . urlencode((string)$post('tab', 'verses')));
    }
    $tab = in_array($_GET['tab'] ?? 'verses', ['verses', 'studies', 'reflections'], true) ? ($_GET['tab'] ?? 'verses') : 'verses';
    $app->render('saved', ['tab' => $tab], 'Saved', 'saved');
    exit;
}

if ($path === '/settings') {
    $flash = null;
    if ($method === 'POST') {
        $s = &$app->settings;
        switch ((string)$post('action')) {
            case 'schedule':
                foreach ($s['sessions'] as $i => $sess) {
                    $t = (string)$post('time_' . $sess['id'], '');
                    if (preg_match('/^([01]\d|2[0-3]):([0-5]\d)$/', $t, $mm)) {
                        $s['sessions'][$i]['minutes'] = (int)$mm[1] * 60 + (int)$mm[2];
                    }
                    $s['sessions'][$i]['enabled'] = $post('on_' . $sess['id']) === '1';
                }
                break;
            case 'reading':
                $ids = array_map(fn($t) => (int)$t['id'], $app->quran->englishTranslations());
                $s['translation_id'] = in_array((int)$post('translation_id'), $ids, true) ? (int)$post('translation_id') : 1;
                $s['transliteration'] = $post('transliteration') === '1';
                $s['arabic_scale'] = max(0.8, min(1.8, (float)$post('arabic_scale', 1)));
                $s['reciter'] = array_key_exists((string)$post('reciter'), App::RECITERS) ? (string)$post('reciter') : 'Alafasy_128kbps';
                $s['verses_per_study'] = in_array((int)$post('verses_per_study'), [1, 2, 3, 5], true) ? (int)$post('verses_per_study') : 3;
                $s['online'] = $post('online') === '1';
                $s['theme'] = in_array($post('theme'), ['system', 'light', 'dark'], true) ? $post('theme') : 'system';
                break;
            case 'new_journey':
                $s['journey'] = (int)$s['journey'] + 1;
                break;
            case 'restore':
                unset($s);
                if ($app->restore((string)$post('code'))) {
                    App::redirect('/?restored=1');
                }
                App::redirect('/settings?err=code#device');
            case 'erase':
                unset($s);
                $app->store->deleteProfile($app->profile);
                setcookie('qj_token', '', ['expires' => 1, 'path' => '/']);
                App::redirect('/welcome');
        }
        unset($s);
        $app->save();
        App::redirect('/settings?saved=1');
    }
    $app->render('settings', [], 'You', 'settings');
    exit;
}

if ($path === '/export.json') {
    header('Content-Type: application/json; charset=utf-8');
    header('Content-Disposition: attachment; filename="quran-journey-export.json"');
    echo json_encode($app->store->export($app->profile, $app->settings), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
    exit;
}

// Calendar reminders: three daily repeating events at the user's session times.
if ($path === '/calendar.ics') {
    header('Content-Type: text/calendar; charset=utf-8');
    header('Content-Disposition: attachment; filename="quran-journey-sessions.ics"');
    $tz = $app->settings['tz'];
    $host = preg_replace('/[^a-zA-Z0-9.:-]/', '', $_SERVER['HTTP_HOST'] ?? 'localhost');
    $base = (App::https() ? 'https://' : 'http://') . $host;
    $day = $app->now()->format('Ymd');
    $lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//The Quran Journey//Sessions//EN', 'CALSCALE:GREGORIAN'];
    foreach ($app->settings['sessions'] as $s) {
        if (!$s['enabled']) {
            continue;
        }
        $t = sprintf('%02d%02d00', intdiv($s['minutes'], 60), $s['minutes'] % 60);
        array_push($lines, 'BEGIN:VEVENT', "UID:qj-{$s['id']}-" . substr($app->profile, 0, 12) . "@quranjourney",
            'DTSTAMP:' . gmdate('Ymd\THis\Z'), "DTSTART;TZID=$tz:{$day}T$t", 'DURATION:PT10M', 'RRULE:FREQ=DAILY',
            "SUMMARY:{$s['label']} · Quran study", 'DESCRIPTION:Your next 3 verses are ready.', "URL:$base/next",
            'BEGIN:VALARM', 'ACTION:DISPLAY', 'DESCRIPTION:Your next 3 verses are ready.', 'TRIGGER:PT0M', 'END:VALARM', 'END:VEVENT');
    }
    $lines[] = 'END:VCALENDAR';
    echo implode("\r\n", $lines) . "\r\n";
    exit;
}

if ($path === '/sources') {
    $app->render('sources', [], 'Sources & methodology', 'settings');
    exit;
}

if ($path === '/privacy') {
    $app->render('privacy', [], 'Privacy', 'settings');
    exit;
}

http_response_code(404);
$app->render('notfound', [], 'Not found', '');
