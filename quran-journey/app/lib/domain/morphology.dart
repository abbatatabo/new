import 'models.dart';

/// Expands the Quranic Arabic Corpus (v0.4) morphological tags into plain
/// English, using ONLY the corpus' published tagset documentation
/// (https://corpus.quran.com/documentation/tagset.jsp and
/// https://corpus.quran.com/documentation/morphologicalfeatures.jsp).
/// It does not infer anything the corpus does not state; unknown tags are
/// shown verbatim.
class Morphology {
  static const posNames = {
    'N': 'Noun',
    'PN': 'Proper noun',
    'ADJ': 'Adjective',
    'IMPN': 'Imperative verbal noun',
    'PRON': 'Personal pronoun',
    'DEM': 'Demonstrative pronoun',
    'REL': 'Relative pronoun',
    'T': 'Time adverb',
    'LOC': 'Location adverb',
    'V': 'Verb',
    'P': 'Preposition',
    'EMPH': 'Emphatic lām',
    'IMPV': 'Imperative lām',
    'PRP': 'Purpose lām',
    'CONJ': 'Coordinating conjunction',
    'SUB': 'Subordinating conjunction',
    'ACC': 'Accusative particle',
    'AMD': 'Amendment particle',
    'ANS': 'Answer particle',
    'AVR': 'Aversion particle',
    'CAUS': 'Particle of cause',
    'CERT': 'Particle of certainty',
    'CIRC': 'Circumstantial particle',
    'COM': 'Comitative particle',
    'COND': 'Conditional particle',
    'EQ': 'Equalization particle',
    'EXH': 'Exhortation particle',
    'EXL': 'Explanation particle',
    'EXP': 'Exceptive particle',
    'FUT': 'Future particle',
    'INC': 'Inceptive particle',
    'INT': 'Particle of interpretation',
    'INTG': 'Interrogative particle',
    'NEG': 'Negative particle',
    'PREV': 'Preventive particle',
    'PRO': 'Prohibition particle',
    'REM': 'Resumption particle',
    'RES': 'Restriction particle',
    'RET': 'Retraction particle',
    'RSLT': 'Result particle',
    'SUP': 'Supplemental particle',
    'SUR': 'Surprise particle',
    'VOC': 'Vocative particle',
    'INL': 'Quranic initials (disconnected letters)',
    'DET': 'Determiner (al-)',
  };

  static const featureNames = {
    'NOM': 'nominative',
    'ACC': 'accusative',
    'GEN': 'genitive',
    'PERF': 'perfect aspect',
    'IMPF': 'imperfect aspect',
    'IMPV': 'imperative',
    'PASS': 'passive voice',
    'ACT': 'active',
    'PCPL': 'participle',
    'VN': 'verbal noun',
    'DEF': 'definite',
    'INDEF': 'indefinite',
    'MOOD:IND': 'indicative mood',
    'MOOD:SUBJ': 'subjunctive mood',
    'MOOD:JUS': 'jussive mood',
  };

  static const _forms = {
    '(I)': 'form I', '(II)': 'form II', '(III)': 'form III', '(IV)': 'form IV',
    '(V)': 'form V', '(VI)': 'form VI', '(VII)': 'form VII', '(VIII)': 'form VIII',
    '(IX)': 'form IX', '(X)': 'form X', '(XI)': 'form XI', '(XII)': 'form XII',
  };

  static const _prefixes = {
    'Al+': 'definite article al-',
    'bi+': 'preposition bi (with/by)',
    'ka+': 'preposition ka (like)',
    'ta+': 'preposition ta (oath)',
    'l:P+': 'preposition li (for/to)',
    'w:P+': 'preposition wa (oath)',
    'w:CONJ+': 'conjunction wa',
    'f:CONJ+': 'conjunction fa',
    'f:REM+': 'resumption particle fa',
    'w:REM+': 'resumption particle wa',
    'w:CIRC+': 'circumstantial particle wa',
    'w:SUP+': 'supplemental particle wa',
    'f:SUP+': 'supplemental particle fa',
    'f:RSLT+': 'result particle fa',
    'f:CAUS+': 'cause particle fa',
    'w:COM+': 'comitative particle wa',
    'A:INTG+': 'interrogative alif',
    'A:EQ+': 'equalization particle a-',
    'l:EMPH+': 'emphatic lām',
    'l:IMPV+': 'imperative lām',
    'l:PRP+': 'purpose lām',
    'sa+': 'future particle sa',
    'ya+': 'vocative particle yā',
    'ha+': 'attention particle hā',
  };

  /// Readable description of one segment, e.g.
  /// "Noun · masculine · genitive".
  static String describe(WordSegment seg) {
    final parts = seg.features.split('|');
    final kind = parts.isEmpty ? '' : parts.first; // PREFIX | STEM | SUFFIX
    if (kind == 'PREFIX') {
      final p = parts.length > 1 ? parts[1] : '';
      return 'Prefix: ${_prefixes[p] ?? posNames[seg.tag] ?? p}';
    }
    if (kind == 'SUFFIX') {
      final p = parts.length > 1 ? parts[1] : '';
      if (p.startsWith('PRON:')) return 'Suffix: attached pronoun (${_pgn(p.substring(5))})';
      if (p == '+VOC') return 'Suffix: vocative';
      if (p == '+n:EMPH') return 'Suffix: emphatic nūn';
      return 'Suffix: $p';
    }
    final out = <String>[posNames[seg.tag] ?? seg.tag];
    for (final f in parts.skip(1)) {
      if (f.startsWith('POS:') || f.startsWith('LEM:') || f.startsWith('ROOT:')) continue;
      if (f.startsWith('SP:')) {
        out.add('special group: ${f.substring(3)}');
        continue;
      }
      if (_forms.containsKey(f)) {
        out.add(_forms[f]!);
      } else if (featureNames.containsKey(f)) {
        out.add(featureNames[f]!);
      } else if (RegExp(r'^[123]?[MF]?[SDP]?$').hasMatch(f) && f.isNotEmpty) {
        out.add(_pgn(f));
      } else {
        out.add(f);
      }
    }
    return out.join(' · ');
  }

  /// Person / gender / number, e.g. 3MS -> "3rd person masculine singular".
  static String _pgn(String s) {
    final words = <String>[];
    for (final ch in s.split('')) {
      switch (ch) {
        case '1': words.add('1st person');
        case '2': words.add('2nd person');
        case '3': words.add('3rd person');
        case 'M': words.add('masculine');
        case 'F': words.add('feminine');
        case 'S': words.add('singular');
        case 'D': words.add('dual');
        case 'P': words.add('plural');
        default: words.add(ch);
      }
    }
    return words.join(' ');
  }

  static String stemPos(Word w) => posNames[w.pos] ?? (w.pos ?? '—');

  /// Extended Buckwalter -> Arabic (1:1 character encoding of the corpus).
  static const _bw = {
    "'": 'ء', '>': 'أ', '&': 'ؤ', '<': 'إ', '}': 'ئ',
    'A': 'ا', 'b': 'ب', 'p': 'ة', 't': 'ت', 'v': 'ث',
    'j': 'ج', 'H': 'ح', 'x': 'خ', 'd': 'د', '*': 'ذ',
    'r': 'ر', 'z': 'ز', 's': 'س', r'$': 'ش', 'S': 'ص',
    'D': 'ض', 'T': 'ط', 'Z': 'ظ', 'E': 'ع', 'g': 'غ',
    '_': 'ـ', 'f': 'ف', 'q': 'ق', 'k': 'ك', 'l': 'ل',
    'm': 'م', 'n': 'ن', 'h': 'ه', 'w': 'و', 'Y': 'ى',
    'y': 'ي', 'F': 'ً', 'N': 'ٌ', 'K': 'ٍ', 'a': 'َ',
    'u': 'ُ', 'i': 'ِ', '~': 'ّ', 'o': 'ْ', '^': 'ٓ',
    '#': 'ٔ', '`': 'ٰ', '{': 'ٱ', ':': 'ۜ', '@': '۟',
    '"': '۠', '[': 'ۢ', ';': 'ۣ', ',': 'ۥ', '.': 'ۦ',
    '!': 'ۨ', '-': '۪', '+': '۫', '%': '۬', ']': 'ۭ',
    ' ': ' ',
  };

  static String bwToArabic(String s) {
    final b = StringBuffer();
    for (final ch in s.replaceAll(RegExp(r'\d+$'), '').split('')) {
      b.write(_bw[ch] ?? ch);
    }
    return b.toString();
  }
}
