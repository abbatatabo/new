import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import 'common.dart';
import 'theme.dart';

/// The four content categories are never mixed and are always labelled.
const categoryLabels = {
  'direct_quotation': 'Direct quotation',
  'paraphrase': 'Paraphrase',
  'editorial_summary': 'Editorial summary',
  'ai_assisted': 'AI-assisted explanation',
};

const categoryHelp = {
  'direct_quotation': 'The exact words of the named work.',
  'paraphrase': "A close restatement of the named work's point, not its exact words.",
  'editorial_summary': "The app editors' summary of the cited sources.",
  'ai_assisted': 'Drafted with AI help, then checked against the cited sources and approved by a reviewer. It is not a scholar\'s words.',
};

class CategoryTag extends StatelessWidget {
  final String category;
  const CategoryTag(this.category, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final ai = category == 'ai_assisted';
    return Tag(
      categoryLabels[category] ?? category,
      icon: switch (category) {
        'direct_quotation' => Icons.format_quote,
        'paraphrase' => Icons.short_text,
        'editorial_summary' => Icons.edit_note,
        _ => Icons.auto_awesome_outlined,
      },
      color: ai ? const Color(0xFF8A5A00) : p.accent,
      background: ai ? const Color(0x1FE0A800) : p.accentSoft,
    );
  }
}

/// A published CMS item with full attribution.
class CmsItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const CmsItemCard({super.key, required this.item});

  Future<Map<String, dynamic>?> _lookup(AppState st, String kind, String? id) async {
    if (id == null) return null;
    final raw = await st.userDb.kvGet('cms_$kind');
    if (raw == null) return null;
    for (final e in (jsonDecode(raw) as List).cast<Map>()) {
      if (e['id'] == id) return e.cast<String, dynamic>();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final p = Palette.of(context);
    final t = Theme.of(context).textTheme;
    final citation = (item['citation'] as Map?)?.cast<String, dynamic>() ?? const {};
    final body = (item['body'] as String? ?? '').split(RegExp(r'\n\s*\n'));
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          CategoryTag(item['category'] as String? ?? ''),
          Tag('Reviewed & approved', icon: Icons.verified_outlined, color: p.success),
        ]),
        if (item['title'] != null) ...[
          const SizedBox(height: 12),
          Text(item['title'] as String, style: t.titleMedium),
        ],
        const SizedBox(height: 10),
        for (final para in body)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SelectableText(
              para.trim(),
              style: item['category'] == 'direct_quotation'
                  ? serif(17, color: p.ink, italic: true, height: 1.5)
                  : serif(17, color: p.ink, height: 1.5),
            ),
          ),
        FutureBuilder<List<Map<String, dynamic>?>>(
          future: Future.wait([
            _lookup(st, 'sources', item['source_id'] as String?),
            _lookup(st, 'scholars', item['scholar_id'] as String?),
          ]),
          builder: (c, s) {
            final src = s.data?[0];
            final sch = s.data?[1];
            final parts = <String>[
              if (sch != null) sch['name'] as String,
              if (src != null) src['title'] as String,
              if (citation['edition'] != null) 'ed. ${citation['edition']}',
              if (citation['volume'] != null) 'vol. ${citation['volume']}',
              if (citation['page'] != null) 'p. ${citation['page']}',
              '${st.surahName(item['surah'] as int)} ${item['surah']}:${item['start_ayah']}'
                  '${item['end_ayah'] != item['start_ayah'] ? '–${item['end_ayah']}' : ''}',
            ];
            final url = (citation['url'] ?? src?['url']) as String?;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Source: ${parts.join(' · ')}', style: t.bodySmall),
              if (item['reviewer'] != null || item['verified_at'] != null)
                Text(
                  'Reviewed${item['reviewer'] != null ? ' by ${item['reviewer']}' : ''}'
                  '${item['verified_at'] != null ? ' · ${(item['verified_at'] as String).split('T').first}' : ''}',
                  style: t.bodySmall,
                ),
              if (url != null && url.startsWith('https://'))
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Source link'),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}

class ContentLegend extends StatelessWidget {
  const ContentLegend({super.key});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('HOW CONTENT IS LABELLED', style: t.labelSmall),
        const SizedBox(height: 8),
        for (final e in categoryLabels.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CategoryTag(e.key),
              const SizedBox(width: 10),
              Expanded(child: Text(categoryHelp[e.key]!, style: t.bodySmall)),
            ]),
          ),
      ]),
    );
  }
}
