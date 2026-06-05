// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

void Function(html.Event)? _listener;

/// Web: browser tab hide/show (Flutter lifecycle is unreliable on web).
void bindWebTabVisibility(void Function(bool visible) onChange) {
  unbindWebTabVisibility();
  _listener = (_) {
    final hidden = html.document.hidden ?? false;
    onChange(!hidden);
  };
  html.document.addEventListener('visibilitychange', _listener);
  onChange(!(html.document.hidden ?? false));
}

void unbindWebTabVisibility() {
  if (_listener != null) {
    html.document.removeEventListener('visibilitychange', _listener);
    _listener = null;
  }
}
