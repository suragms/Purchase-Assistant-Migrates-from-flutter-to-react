/// Central exports for user-facing errors and load states.
///
/// Repositories and services should map exceptions to these helpers; UI should
/// import from here instead of reaching into multiple `core` paths.
library;

export '../auth/auth_error_messages.dart'
    show
        AuthErrorContext,
        friendlyApiError,
        friendlyAuthError,
        friendlyGoogleSignInError;
export '../widgets/friendly_load_error.dart'
    show FriendlyLoadError, kFriendlyLoadNetworkSubtitle;
export '../widgets/hexa_error_card.dart'
    show HexaErrorCard, InlineLoadError;
export 'load_state_error.dart' show loadStateErrorSubtitle;
