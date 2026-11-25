<?php
declare(strict_types=1);

namespace QJ;

require_once __DIR__ . '/Plan.php';
require_once __DIR__ . '/Data.php';
require_once __DIR__ . '/Online.php';

/** Escape for HTML. */
function h(mixed $s): string
{
    return htmlspecialchars((string)$s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function fmt(int $n): string
{
    return number_format($n);
}

function hm(int $m): string
{
    return sprintf('%02d:%02d', intdiv($m, 60), $m % 60);
}

final class App
{
    public const NAME = 'The Quran Journey';
    public const TAGLINE = '3 verses. 3 moments. Every day.';
    private const COOKIE = 'qj_token';

    public Quran $quran;
    public UserStore $store;
    public Online $online;
    public string $profile = '';
    public string $token = '';
    public array $settings = [];
    public ?Plan $plan = null;
    public ?Progress $progress = null;
    private array $groupings = [];

    public static function defaults(): array
    {
        return [
            'onboarded' => false,
            'sessions' => [
                ['id' => 'morning', 'label' => 'Morning', 'minutes' => 420, 'enabled' => true],
                ['id' => 'afternoon', 'label' => 'Afternoon', 'minutes' => 810, 'enabled' => true],
                ['id' => 'evening', 'label' => 'Evening', 'minutes' => 1200, 'enabled' => true],
            ],
            'translation_id' => 1,
            'transliteration' => true,
            'arabic_scale' => 1.0,
            'theme' => 'system',
            'verses_per_study' => 3,
            'journey' => 1,
            'tz' => 'UTC',
            'reciter' => 'Alafasy_128kbps',
            'online' => true,
        ];
    }

    public const RECITERS = [
        'Alafasy_128kbps' => 'Mishary Rashid Alafasy',
        'Husary_128kbps' => 'Mahmoud Khalil al-Husary',
        'Minshawy_Murattal_128kbps' => 'Mohamed Siddiq al-Minshawi',
        'Abdul_Basit_Murattal_192kbps' => 'Abdul Basit Abdus-Samad',
    ];

    public function __construct()
    {
        $root = dirname(__DIR__);
        $this->quran = new Quran(getenv('QJ_QURAN_DB') ?: dirname($root) . '/app/assets/db/quran.db');
        $this->store = new UserStore(getenv('QJ_WEB_DB') ?: $root . '/data/web.sqlite');
        $this->online = new Online($this->store, getenv('QJ_API_BASE_URL') ?: '');
        $g = json_decode((string)@file_get_contents(dirname($root) . '/app/assets/content/groupings.json'), true);
        $this->groupings = $g['groupings'] ?? [];
    }

    // ---------------------------------------------------------- identity
    public function boot(): void
    {
        $tok = $_COOKIE[self::COOKIE] ?? '';
        if (!is_string($tok) || !preg_match('/^[a-f0-9]{48}$/', $tok)) {
            $tok = bin2hex(random_bytes(24));
            $this->setCookie($tok);
        }
        $this->token = $tok;
        $this->profile = hash('sha256', $tok);
        $this->settings = $this->store->ensureProfile($this->profile, self::defaults());
        // Browser time zone (set by app.js) so "today" matches the user's day.
        $tz = $_COOKIE['qj_tz'] ?? '';
        if (is_string($tz) && $tz !== $this->settings['tz'] && in_array($tz, \DateTimeZone::listIdentifiers(), true)) {
            $this->settings['tz'] = $tz;
            $this->store->saveSettings($this->profile, $this->settings);
        }
        $this->rebuild();
    }

    private function setCookie(string $tok): void
    {
        setcookie(self::COOKIE, $tok, [
            'expires' => time() + 60 * 60 * 24 * 730,
            'path' => '/',
            'secure' => self::https(),
            'httponly' => true,
            'samesite' => 'Lax',
        ]);
    }

    public static function https(): bool
    {
        return (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
            || (getenv('QJ_TRUST_PROXY') === '1' && ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
    }

    /** Move this browser onto another profile (transfer code from another device). */
    public function restore(string $code): bool
    {
        $code = strtolower(preg_replace('/[^a-fA-F0-9]/', '', $code) ?? '');
        if (strlen($code) !== 48 || !$this->store->profileExists(hash('sha256', $code))) {
            return false;
        }
        $this->setCookie($code);
        return true;
    }

    public function transferCode(): string
    {
        return strtoupper(implode('-', str_split($this->token, 6)));
    }

    public function csrf(): string
    {
        return hash_hmac('sha256', 'csrf', $this->token);
    }

    public function checkCsrf(): void
    {
        $t = $_POST['_csrf'] ?? '';
        if (!is_string($t) || !hash_equals($this->csrf(), $t)) {
            http_response_code(403);
            exit('Your session expired. Please go back and try again.');
        }
    }

    // ------------------------------------------------------------- state
    public function rebuild(): void
    {
        $vps = (int)$this->settings['verses_per_study'];
        $this->plan = new Plan($this->quran->surahs, $this->quran->wordCounts, $vps === 3 ? $this->groupings : [], $vps);
        $this->progress = new Progress($this->plan, $this->store->completions($this->profile, (int)$this->settings['journey']));
    }

    public function save(): void
    {
        $this->store->saveSettings($this->profile, $this->settings);
        $this->rebuild();
    }

    public function now(): \DateTimeImmutable
    {
        try {
            return new \DateTimeImmutable('now', new \DateTimeZone($this->settings['tz']));
        } catch (\Throwable) {
            return new \DateTimeImmutable('now', new \DateTimeZone('UTC'));
        }
    }

    public function surahName(int $n): string
    {
        return $this->quran->surah($n)['name_translit'];
    }

    public function studyTitle(array $s): string
    {
        return $this->surahName($s['surah']) . ' ' . Plan::refLabel($s);
    }

    public static function studyUrl(array $s): string
    {
        return "/study/{$s['start']}-{$s['end']}";
    }

    public function translation(): array
    {
        return $this->quran->translation((int)$this->settings['translation_id']);
    }

    // ------------------------------------------------------------ output
    public static function securityHeaders(): void
    {
        header("Content-Security-Policy: default-src 'self'; img-src 'self' data:; media-src https://everyayah.com; style-src 'self'; style-src-attr 'unsafe-inline'; script-src 'self'; font-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'");
        header('X-Content-Type-Options: nosniff');
        header('Referrer-Policy: same-origin');
        header('Permissions-Policy: camera=(), microphone=(), geolocation=()');
        if (self::https()) {
            header('Strict-Transport-Security: max-age=31536000');
        }
    }

    /** Render a view inside the layout. */
    public function render(string $view, array $vars = [], string $title = '', string $nav = ''): void
    {
        $app = $this;
        extract($vars, EXTR_SKIP);
        ob_start();
        require __DIR__ . "/views/$view.php";
        $content = ob_get_clean();
        require __DIR__ . '/views/layout.php';
    }

    public static function redirect(string $to): never
    {
        header('Location: ' . $to, true, 303);
        exit;
    }

    public static function ayahMark(int $n): string
    {
        return "\u{06DD}" . strtr((string)$n, ['0' => '٠', '1' => '١', '2' => '٢', '3' => '٣', '4' => '٤', '5' => '٥', '6' => '٦', '7' => '٧', '8' => '٨', '9' => '٩']);
    }

    /** Tanzil transliteration markup -> safe HTML (<u> long vowel, <b> silent letter). */
    public static function translit(string $raw): string
    {
        $raw = str_replace(['</U>', '</B>'], ['</u>', '</b>'], $raw);
        $parts = preg_split('#(<u>.*?</u>|<b>.*?</b>)#i', $raw, -1, PREG_SPLIT_DELIM_CAPTURE | PREG_SPLIT_NO_EMPTY) ?: [];
        $out = '';
        foreach ($parts as $p) {
            if (preg_match('#^<u>(.*)</u>$#i', $p, $m)) {
                $out .= '<span class="long">' . h($m[1]) . '</span>';
            } elseif (preg_match('#^<b>(.*)</b>$#i', $p, $m)) {
                $out .= '<span class="silent">' . h($m[1]) . '</span>';
            } else {
                $out .= h($p);
            }
        }
        return $out;
    }
}
