from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    """Migrated from Laravel `users` (+ optional `otp` for password reset flow)."""

    otp = models.CharField(max_length=10, blank=True, null=True)

    class Meta:
        db_table = "users"
