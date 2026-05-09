"""
Auth helpers for endpoints that must allow anonymous access without 401 on bad tokens.
"""

from rest_framework.authentication import BaseAuthentication, get_authorization_header
from rest_framework.authtoken.models import Token


class OptionalTokenAuthentication(BaseAuthentication):
    """
    Same wire format as DRF TokenAuthentication (`Authorization: Token <key>`),
    but unknown/revoked keys are treated as anonymous (no AuthenticationFailed / 401).
    Use with `AllowAny` on `user_data`, `doctor_on_call_me`, etc.
    """

    keyword = b"Token"

    def authenticate(self, request):
        auth = get_authorization_header(request).split()
        if not auth or auth[0].lower() != self.keyword.lower():
            return None
        if len(auth) != 2:
            return None
        try:
            key = auth[1].decode("utf-8")
        except UnicodeDecodeError:
            return None
        key = key.strip()
        if not key:
            return None
        try:
            token = Token.objects.select_related("user").get(key=key)
        except Token.DoesNotExist:
            return None
        if not token.user.is_active:
            return None
        return (token.user, token)
