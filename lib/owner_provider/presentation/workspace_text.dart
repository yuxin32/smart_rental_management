/// Removes import-only labels from the existing sample dataset at display
/// boundaries. Never use this for IDs, saved payloads, search filters, tokens,
/// authorization or deciding whether a service was actually performed.
/// Ordinary user text, including the word "test", is left unchanged.
String workspaceText(String value) {
  if (!value.contains('[UAT]')) return value;
  var text = value.replaceAll('[UAT]', '').trim();
  if (text.startsWith('Synthetic scenario ') ||
      text.startsWith('Synthetic completion scenario.')) return '';
  if (text == 'Historical fixture acceptance' ||
      text == 'Synthetic service started' ||
      text == 'Fixture completion verified') return '';
  if (text == 'Schedule changed during acceptance testing')
    return 'Schedule changed';
  if (text ==
      'Fictional rental address, Kuala Lumpur. No real resident or access code.')
    return 'Kuala Lumpur';
  text = text
      .replaceAll(' This is a test request.', '')
      .replaceAll(RegExp(r'\s*Test reply only\.?$'), '');
  return text.replaceAll(RegExp(r',\s*'), ', ').trim();
}
