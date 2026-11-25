<?php
declare(strict_types=1);

namespace QJ;

/**
 * Study grouping + verse-based progression.
 * A line-for-line port of app/lib/domain/grouping.dart and progress.dart;
 * tests/run.php checks that both produce the identical plan.
 */
final class Plan
{
    /** @var list<array{index:int,surah:int,start_ayah:int,end_ayah:int,start:int,end:int,rationale:?string}> */
    public array $studies = [];
    /** @var array<int,int> verse id => study index */
    private array $byVerse = [];
    public int $totalVerses = 0;

    /**
     * @param list<array{number:int,ayah_count:int,first_verse_id:int}> $surahs
     * @param array<int,int> $wordCounts verse id => word count
     * @param list<array{surah:int,start_ayah:int,end_ayah:int,rationale:string}> $overrides
     */
    public function __construct(array $surahs, array $wordCounts, array $overrides = [], public int $versesPerStudy = 3, public int $maxWords = 75)
    {
        $bySurah = [];
        foreach ($overrides as $o) {
            $bySurah[$o['surah']][] = $o;
        }
        foreach ($surahs as $s) {
            $this->totalVerses += $s['ayah_count'];
            $valid = self::validOverrides($s, $bySurah[$s['number']] ?? []);
            $groups = [];
            $ayah = 1;
            $oi = 0;
            while ($ayah <= $s['ayah_count']) {
                if ($oi < count($valid) && $valid[$oi]['start_ayah'] === $ayah) {
                    $o = $valid[$oi++];
                    $groups[] = [$o['start_ayah'], $o['end_ayah'], $o['rationale']];
                    $ayah = $o['end_ayah'] + 1;
                    continue;
                }
                $limit = $oi < count($valid) ? $valid[$oi]['start_ayah'] - 1 : $s['ayah_count'];
                $start = $ayah;
                $end = $ayah;
                $words = $wordCounts[$s['first_verse_id'] + $ayah - 1] ?? 0;
                while ($end - $start + 1 < $versesPerStudy && $end < $limit) {
                    $next = $wordCounts[$s['first_verse_id'] + $end] ?? 0;
                    if ($words + $next > $maxWords) {
                        break;
                    }
                    $words += $next;
                    $end++;
                }
                $groups[] = [$start, $end, null];
                $ayah = $end + 1;
            }
            // Merge a lone final verse into the previous rule-made group.
            $n = count($groups);
            if ($n >= 2) {
                $last = $groups[$n - 1];
                $prev = $groups[$n - 2];
                if ($last[0] === $last[1] && $last[2] === null && $prev[2] === null && $versesPerStudy > 1) {
                    $w = 0;
                    for ($a = $prev[0]; $a <= $last[1]; $a++) {
                        $w += $wordCounts[$s['first_verse_id'] + $a - 1] ?? 0;
                    }
                    if ($w <= $maxWords) {
                        $groups[$n - 2][1] = $last[1];
                        array_pop($groups);
                    }
                }
            }
            foreach ($groups as [$a0, $a1, $why]) {
                $st = [
                    'index' => count($this->studies),
                    'surah' => $s['number'],
                    'start_ayah' => $a0,
                    'end_ayah' => $a1,
                    'start' => $s['first_verse_id'] + $a0 - 1,
                    'end' => $s['first_verse_id'] + $a1 - 1,
                    'rationale' => $why,
                ];
                for ($v = $st['start']; $v <= $st['end']; $v++) {
                    $this->byVerse[$v] = $st['index'];
                }
                $this->studies[] = $st;
            }
        }
        for ($v = 1; $v <= $this->totalVerses; $v++) {
            if (!isset($this->byVerse[$v])) {
                throw new \RuntimeException("Verse $v not covered by the study plan");
            }
        }
    }

    private static function validOverrides(array $s, array $list): array
    {
        usort($list, fn($a, $b) => $a['start_ayah'] <=> $b['start_ayah']);
        $out = [];
        $lastEnd = 0;
        foreach ($list as $o) {
            if ($o['start_ayah'] >= 1 && $o['end_ayah'] <= $s['ayah_count'] && $o['start_ayah'] <= $o['end_ayah'] && $o['start_ayah'] > $lastEnd) {
                $out[] = $o;
                $lastEnd = $o['end_ayah'];
            }
        }
        return $out;
    }

    public function count(): int
    {
        return count($this->studies);
    }

    public function forVerse(int $id): array
    {
        return $this->studies[$this->byVerse[max(1, min($this->totalVerses, $id))]];
    }

    public function byRange(int $start, int $end): ?array
    {
        if ($start < 1 || $start > $this->totalVerses) {
            return null;
        }
        $s = $this->forVerse($start);
        return ($s['start'] === $start && $s['end'] === $end) ? $s : null;
    }

    public static function refLabel(array $s): string
    {
        return $s['start_ayah'] === $s['end_ayah']
            ? "{$s['surah']}:{$s['start_ayah']}"
            : "{$s['surah']}:{$s['start_ayah']}–{$s['end_ayah']}";
    }
}

/** Progress = the set of completed verses (never date-based). */
final class Progress
{
    /** @var array<int,bool> */
    private array $done = [];
    private int $frontier = 0;

    /** @param list<array{start_id:int,end_id:int,completed_at:int}> $completions chronological */
    public function __construct(public Plan $plan, public array $completions)
    {
        usort($this->completions, fn($a, $b) => $a['completed_at'] <=> $b['completed_at']);
        foreach ($this->completions as $c) {
            for ($v = max(1, $c['start_id']); $v <= min($plan->totalVerses, $c['end_id']); $v++) {
                $this->done[$v] = true;
            }
        }
        while ($this->frontier < $plan->count() && $this->isStudyComplete($plan->studies[$this->frontier])) {
            $this->frontier++;
        }
    }

    public function isVerseComplete(int $id): bool
    {
        return isset($this->done[$id]);
    }

    public function isStudyComplete(array $s): bool
    {
        for ($v = $s['start']; $v <= $s['end']; $v++) {
            if (!isset($this->done[$v])) {
                return false;
            }
        }
        return true;
    }

    public function completedVerses(): int
    {
        return count($this->done);
    }

    public function fraction(): float
    {
        return $this->completedVerses() / $this->plan->totalVerses;
    }

    public function next(): ?array
    {
        return $this->frontier < $this->plan->count() ? $this->plan->studies[$this->frontier] : null;
    }

    public function upcoming(int $n): array
    {
        $out = [];
        for ($i = $this->frontier; $i < $this->plan->count() && count($out) < $n; $i++) {
            if (!$this->isStudyComplete($this->plan->studies[$i])) {
                $out[] = $this->plan->studies[$i];
            }
        }
        return $out;
    }

    /** Distinct completions on the local date of $now (Y-m-d in $tz). */
    public function completedOn(\DateTimeImmutable $now): array
    {
        $day = $now->format('Y-m-d');
        $seen = [];
        $out = [];
        foreach ($this->completions as $c) {
            $d = (new \DateTimeImmutable('@' . intdiv($c['completed_at'], 1000)))->setTimezone($now->getTimezone())->format('Y-m-d');
            $k = $c['start_id'] . '-' . $c['end_id'];
            if ($d === $day && !isset($seen[$k])) {
                $seen[$k] = true;
                $out[] = $c;
            }
        }
        return $out;
    }

    /**
     * Today's slots: completed-today first, then the next unread studies.
     * @return list<array{session:array,study:array,state:string}>
     */
    public function today(array $sessions, \DateTimeImmutable $now): array
    {
        $enabled = array_values(array_filter($sessions, fn($s) => $s['enabled']));
        usort($enabled, fn($a, $b) => $a['minutes'] <=> $b['minutes']);
        $doneToday = $this->completedOn($now);
        $nowMin = (int)$now->format('G') * 60 + (int)$now->format('i');
        $pending = $this->upcoming(count($enabled));
        $slots = [];
        $pi = 0;
        foreach ($enabled as $i => $s) {
            if ($i < count($doneToday)) {
                $slots[] = ['session' => $s, 'study' => $this->plan->forVerse($doneToday[$i]['start_id']), 'state' => 'done'];
            } elseif ($pi < count($pending)) {
                $slots[] = ['session' => $s, 'study' => $pending[$pi++], 'state' => $s['minutes'] <= $nowMin ? 'ready' : 'upcoming'];
            }
        }
        return $slots;
    }

    /** @return array<int,int> surah => completed verses */
    public function surahCounts(array $surahs): array
    {
        $out = [];
        foreach ($surahs as $s) {
            $n = 0;
            for ($v = $s['first_verse_id']; $v < $s['first_verse_id'] + $s['ayah_count']; $v++) {
                if (isset($this->done[$v])) {
                    $n++;
                }
            }
            $out[$s['number']] = $n;
        }
        return $out;
    }

    public function completedStudies(): array
    {
        $seen = [];
        $out = [];
        foreach (array_reverse($this->completions) as $c) {
            $s = $this->plan->forVerse($c['start_id']);
            if ($this->isStudyComplete($s) && !isset($seen[$s['index']])) {
                $seen[$s['index']] = true;
                $out[] = $s;
            }
        }
        return $out;
    }
}
