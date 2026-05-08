from django.contrib import admin
from django.urls import include, path
from django.conf import settings
from django.conf.urls.static import static
from emr import views as emr_views

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/", include("emr.urls")),
    path("reset-password/<str:uid>/<str:token>/", emr_views.password_reset_page),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
