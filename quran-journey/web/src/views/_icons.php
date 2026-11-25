<?php
/** Small inline SVG icon set (stroke icons). */
function qj_icon(string $name): string
{
    $p = [
        'morning' => '<path d="M4 18h16M7 14a5 5 0 0 1 10 0M12 4v3M5.2 7.2l2 2M18.8 7.2l-2 2"/>',
        'afternoon' => '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
        'evening' => '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>',
        'check' => '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
        'chev' => '<path d="M9 6l6 6-6 6"/>',
        'bookmark' => '<path d="M7 4h10v16l-5-3.5L7 20z"/>',
        'play' => '<circle cx="12" cy="12" r="9"/><path d="M10 8.5l5.5 3.5-5.5 3.5z"/>',
        'back' => '<path d="M15 6l-6 6 6 6"/>',
        'prev' => '<path d="M7 6v12M18 6l-8 6 8 6z"/>',
        'next' => '<path d="M17 6v12M6 6l8 6-8 6z"/>',
        'replay' => '<path d="M4 12a8 8 0 1 0 3-6.2M4 4v5h5"/>',
        'external' => '<path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>',
    ][$name] ?? '';
    return '<svg viewBox="0 0 24 24" aria-hidden="true">' . $p . '</svg>';
}
