/// Normaliza um texto para comparação: minúsculas e sem acentos.
/// Usado na pesquisa para que "acao" encontre "Ação".
String normalizeText(String input) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';

  final buffer = StringBuffer();
  for (final char in input.toLowerCase().split('')) {
    final index = from.indexOf(char);
    buffer.write(index >= 0 ? to[index] : char);
  }
  return buffer.toString();
}

/// Formata milissegundos (epoch) como `dd/MM/aaaa HH:mm`.
String formatDateTime(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}
