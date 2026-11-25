<?php
declare(strict_types=1);

namespace QJ;

/**
 * Online sources (server-side fetch, cached in SQLite):
 *  - Quran.com word-by-word glosses
 *  - Classical Arabic tafsir (verbatim, public-domain works)
 *  - Published CMS content from the optional backend
 */
final class Online
{
    public const TAFSIRS = [
        14 => ['Ibn Kathir', 'ابن كثير', 774, 1373, "Tafsir al-Qur'an al-'Azim", 'ar-tafsir-ibn-kathir'],
        15 => ['al-Tabari', 'الطبري', 310, 923, "Jami' al-Bayan 'an Ta'wil Ay al-Qur'an", 'ar-tafsir-al-tabari'],
        90 => ['al-Qurtubi', 'القرطبي', 671, 1273, "al-Jami' li-Ahkam al-Qur'an", 'ar-tafseer-al-qurtubi'],
        94 => ['al-Baghawi', 'البغوي', 516, 1122, "Ma'alim al-Tanzil", 'ar-tafsir-al-baghawi'],
    ];

    private const API = 'https://api.quran.com/api/v4';

    public function __construct(private UserStore $store, private string $cmsBase = '')
    {
    }

    private function get(string $url, int $timeout = 10): ?array
    {
        $body = null;
        if (function_exists('curl_init')) {
            // libcurl honours the standard https_proxy / HTTPS_PROXY variables.
            $ch = curl_init($url);
            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => $timeout,
                CURLOPT_CONNECTTIMEOUT => 5,
                CURLOPT_FOLLOWLOCATION => false,
                CURLOPT_PROTOCOLS => CURLPROTO_HTTPS | CURLPROTO_HTTP,
                CURLOPT_HTTPHEADER => ['Accept: application/json', 'User-Agent: QuranJourneyWeb/1.0'],
            ]);
            $ca = getenv('CURL_CA_BUNDLE') ?: getenv('SSL_CERT_FILE');
            if ($ca && is_file($ca)) {
                curl_setopt($ch, CURLOPT_CAINFO, $ca);
            }
            $res = curl_exec($ch);
            $status = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
            $body = ($res !== false && $status === 200) ? (string)$res : null;
        } else {
            $ctx = stream_context_create(['http' => [
                'timeout' => $timeout,
                'ignore_errors' => true,
                'header' => "Accept: application/json\r\nUser-Agent: QuranJourneyWeb/1.0\r\n",
            ]]);
            $res = @file_get_contents($url, false, $ctx);
            $status = 0;
            foreach ($http_response_header ?? [] as $h) {
                if (preg_match('#^HTTP/\S+ (\d{3})#', $h, $m)) {
                    $status = (int)$m[1];
                }
            }
            $body = ($res !== false && $status === 200) ? $res : null;
        }
        if ($body === null) {
            return null;
        }
        $j = json_decode($body, true);
        return is_array($j) ? $j : null;
    }

    /** @return ?list<array{p:int,a:string,t:string,tr:string}> */
    public function glosses(int $surah, int $ayah): ?array
    {
        $key = "wbw:$surah:$ayah";
        if (($c = $this->store->cacheGet($key)) !== null) {
            return json_decode($c, true);
        }
        $j = $this->get(self::API . "/verses/by_key/$surah:$ayah?words=true&word_fields=text_uthmani&language=en");
        if (!$j || !isset($j['verse']['words'])) {
            return null;
        }
        $out = [];
        foreach ($j['verse']['words'] as $w) {
            if (($w['char_type_name'] ?? '') !== 'word') {
                continue;
            }
            $out[] = ['p' => (int)$w['position'], 'a' => (string)($w['text_uthmani'] ?? ''), 't' => (string)($w['translation']['text'] ?? ''), 'tr' => (string)($w['transliteration']['text'] ?? '')];
        }
        $this->store->cachePut($key, json_encode($out, JSON_UNESCAPED_UNICODE));
        return $out;
    }

    /** @return ?array{keys:list<string>,paragraphs:list<string>,url:string} */
    public function tafsir(int $work, int $surah, int $ayah): ?array
    {
        if (!isset(self::TAFSIRS[$work])) {
            return null;
        }
        $key = "tafsir:$work:$surah:$ayah";
        $data = null;
        if (($c = $this->store->cacheGet($key)) !== null) {
            $data = json_decode($c, true);
        } else {
            $j = $this->get(self::API . "/tafsirs/$work/by_ayah/$surah:$ayah", 15);
            if (!$j || !isset($j['tafsir'])) {
                return null;
            }
            $data = ['keys' => array_keys($j['tafsir']['verses'] ?? ["$surah:$ayah" => 1]), 'html' => (string)($j['tafsir']['text'] ?? '')];
            $this->store->cachePut($key, json_encode($data, JSON_UNESCAPED_UNICODE));
        }
        $paras = self::htmlToParagraphs($data['html']);
        if (!$paras) {
            return null;
        }
        return ['keys' => $data['keys'], 'paragraphs' => $paras, 'url' => "https://quran.com/$surah:$ayah/tafsirs/" . self::TAFSIRS[$work][5]];
    }

    /** Converts source HTML to plain paragraphs without altering words. */
    public static function htmlToParagraphs(string $html): array
    {
        $t = preg_replace('#</p>|<br\s*/?>|</h\d>|</div>#i', "\n", $html) ?? '';
        $t = html_entity_decode(strip_tags($t), ENT_QUOTES | ENT_HTML5, 'UTF-8');
        return array_values(array_filter(array_map('trim', explode("\n", $t)), fn($s) => $s !== ''));
    }

    /** Published CMS items for a verse range (only status=published is ever kept). */
    public function cms(int $surah, int $start, int $end): array
    {
        if ($this->cmsBase === '') {
            return [];
        }
        $raw = $this->store->cacheGet('cms:all', 600);
        if ($raw === null) {
            $j = $this->get(rtrim($this->cmsBase, '/') . '/api/content/published?since=', 10);
            if ($j === null) {
                $raw = $this->store->cacheGet('cms:all') ?? '{"items":[],"sources":[],"scholars":[]}';
            } else {
                $j['items'] = array_values(array_filter($j['items'] ?? [], fn($i) => ($i['status'] ?? '') === 'published'));
                $raw = json_encode($j, JSON_UNESCAPED_UNICODE);
                $this->store->cachePut('cms:all', $raw);
            }
        }
        $all = json_decode($raw, true);
        $items = array_filter($all['items'] ?? [], fn($i) => $i['surah'] === $surah && $i['start_ayah'] <= $end && $i['end_ayah'] >= $start);
        $src = array_column($all['sources'] ?? [], null, 'id');
        $sch = array_column($all['scholars'] ?? [], null, 'id');
        return array_map(function ($i) use ($src, $sch) {
            $i['_source'] = $src[$i['source_id'] ?? ''] ?? null;
            $i['_scholar'] = $sch[$i['scholar_id'] ?? ''] ?? null;
            return $i;
        }, array_values($items));
    }
}

/** QAC tagset expansions (same table as app/lib/domain/morphology.dart). */
final class Morphology
{
    public const POS = [
        'N' => 'Noun', 'PN' => 'Proper noun', 'ADJ' => 'Adjective', 'IMPN' => 'Imperative verbal noun',
        'PRON' => 'Personal pronoun', 'DEM' => 'Demonstrative pronoun', 'REL' => 'Relative pronoun',
        'T' => 'Time adverb', 'LOC' => 'Location adverb', 'V' => 'Verb', 'P' => 'Preposition',
        'EMPH' => 'Emphatic lām', 'IMPV' => 'Imperative lām', 'PRP' => 'Purpose lām',
        'CONJ' => 'Coordinating conjunction', 'SUB' => 'Subordinating conjunction', 'ACC' => 'Accusative particle',
        'AMD' => 'Amendment particle', 'ANS' => 'Answer particle', 'AVR' => 'Aversion particle', 'CAUS' => 'Particle of cause',
        'CERT' => 'Particle of certainty', 'CIRC' => 'Circumstantial particle', 'COM' => 'Comitative particle',
        'COND' => 'Conditional particle', 'EQ' => 'Equalization particle', 'EXH' => 'Exhortation particle',
        'EXL' => 'Explanation particle', 'EXP' => 'Exceptive particle', 'FUT' => 'Future particle', 'INC' => 'Inceptive particle',
        'INT' => 'Particle of interpretation', 'INTG' => 'Interrogative particle', 'NEG' => 'Negative particle',
        'PREV' => 'Preventive particle', 'PRO' => 'Prohibition particle', 'REM' => 'Resumption particle',
        'RES' => 'Restriction particle', 'RET' => 'Retraction particle', 'RSLT' => 'Result particle',
        'SUP' => 'Supplemental particle', 'SUR' => 'Surprise particle', 'VOC' => 'Vocative particle',
        'INL' => 'Quranic initials (disconnected letters)', 'DET' => 'Determiner (al-)',
    ];
    private const FEAT = [
        'NOM' => 'nominative', 'ACC' => 'accusative', 'GEN' => 'genitive', 'PERF' => 'perfect aspect',
        'IMPF' => 'imperfect aspect', 'IMPV' => 'imperative', 'PASS' => 'passive voice', 'ACT' => 'active',
        'PCPL' => 'participle', 'VN' => 'verbal noun', 'DEF' => 'definite', 'INDEF' => 'indefinite',
        'MOOD:IND' => 'indicative mood', 'MOOD:SUBJ' => 'subjunctive mood', 'MOOD:JUS' => 'jussive mood',
    ];
    private const PREFIX = [
        'Al+' => 'definite article al-', 'bi+' => 'preposition bi (with/by)', 'ka+' => 'preposition ka (like)',
        'ta+' => 'preposition ta (oath)', 'l:P+' => 'preposition li (for/to)', 'w:P+' => 'preposition wa (oath)',
        'w:CONJ+' => 'conjunction wa', 'f:CONJ+' => 'conjunction fa', 'f:REM+' => 'resumption particle fa',
        'w:REM+' => 'resumption particle wa', 'w:CIRC+' => 'circumstantial particle wa', 'w:SUP+' => 'supplemental particle wa',
        'f:SUP+' => 'supplemental particle fa', 'f:RSLT+' => 'result particle fa', 'f:CAUS+' => 'cause particle fa',
        'w:COM+' => 'comitative particle wa', 'A:INTG+' => 'interrogative alif', 'A:EQ+' => 'equalization particle a-',
        'l:EMPH+' => 'emphatic lām', 'l:IMPV+' => 'imperative lām', 'l:PRP+' => 'purpose lām',
        'sa+' => 'future particle sa', 'ya+' => 'vocative particle yā', 'ha+' => 'attention particle hā',
    ];
    private const BW = [
        "'" => 'ء', '>' => 'أ', '&' => 'ؤ', '<' => 'إ', '}' => 'ئ', 'A' => 'ا', 'b' => 'ب', 'p' => 'ة', 't' => 'ت',
        'v' => 'ث', 'j' => 'ج', 'H' => 'ح', 'x' => 'خ', 'd' => 'د', '*' => 'ذ', 'r' => 'ر', 'z' => 'ز', 's' => 'س',
        '$' => 'ش', 'S' => 'ص', 'D' => 'ض', 'T' => 'ط', 'Z' => 'ظ', 'E' => 'ع', 'g' => 'غ', '_' => 'ـ', 'f' => 'ف',
        'q' => 'ق', 'k' => 'ك', 'l' => 'ل', 'm' => 'م', 'n' => 'ن', 'h' => 'ه', 'w' => 'و', 'Y' => 'ى', 'y' => 'ي',
        'F' => "\u{064B}", 'N' => "\u{064C}", 'K' => "\u{064D}", 'a' => "\u{064E}", 'u' => "\u{064F}", 'i' => "\u{0650}",
        '~' => "\u{0651}", 'o' => "\u{0652}", '^' => "\u{0653}", '#' => "\u{0654}", '`' => "\u{0670}", '{' => 'ٱ',
        ':' => "\u{06DC}", '@' => "\u{06DF}", '"' => "\u{06E0}", '[' => "\u{06E2}", ';' => "\u{06E3}", ',' => "\u{06E5}",
        '.' => "\u{06E6}", '!' => "\u{06E8}", '-' => "\u{06EA}", '+' => "\u{06EB}", '%' => "\u{06EC}", ']' => "\u{06ED}",
    ];

    public static function bw(string $s): string
    {
        return strtr(preg_replace('/\d+$/', '', $s) ?? '', self::BW);
    }

    private static function pgn(string $s): string
    {
        $map = ['1' => '1st person', '2' => '2nd person', '3' => '3rd person', 'M' => 'masculine', 'F' => 'feminine', 'S' => 'singular', 'D' => 'dual', 'P' => 'plural'];
        return implode(' ', array_map(fn($c) => $map[$c] ?? $c, str_split($s)));
    }

    /** @param array{0:string,1:string,2:string} $seg form, tag, features */
    public static function describe(array $seg): string
    {
        [, $tag, $features] = $seg;
        $parts = explode('|', $features);
        $kind = $parts[0] ?? '';
        if ($kind === 'PREFIX') {
            $p = $parts[1] ?? '';
            return 'Prefix: ' . (self::PREFIX[$p] ?? self::POS[$tag] ?? $p);
        }
        if ($kind === 'SUFFIX') {
            $p = $parts[1] ?? '';
            if (str_starts_with($p, 'PRON:')) {
                return 'Suffix: attached pronoun (' . self::pgn(substr($p, 5)) . ')';
            }
            return match ($p) { '+VOC' => 'Suffix: vocative', '+n:EMPH' => 'Suffix: emphatic nūn', default => "Suffix: $p" };
        }
        $out = [self::POS[$tag] ?? $tag];
        foreach (array_slice($parts, 1) as $f) {
            if (str_starts_with($f, 'POS:') || str_starts_with($f, 'LEM:') || str_starts_with($f, 'ROOT:')) {
                continue;
            }
            if (str_starts_with($f, 'SP:')) {
                $out[] = 'special group: ' . substr($f, 3);
            } elseif (preg_match('/^\((I|II|III|IV|V|VI|VII|VIII|IX|X|XI|XII)\)$/', $f, $m)) {
                $out[] = 'form ' . $m[1];
            } elseif (isset(self::FEAT[$f])) {
                $out[] = self::FEAT[$f];
            } elseif ($f !== '' && preg_match('/^[123]?[MF]?[SDP]?$/', $f)) {
                $out[] = self::pgn($f);
            } else {
                $out[] = $f;
            }
        }
        return implode(' · ', $out);
    }
}
