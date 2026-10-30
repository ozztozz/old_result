"""
URL configuration for yuzme_projesi project.
"""
from django.contrib import admin
from django.urls import path, include, re_path
from django.conf import settings
from django.views.static import serve

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/v1/', include('mobile_api.urls')),
    path('', include('sonuclar.urls')),
]

# Development / WSGI altında statik dosyaların doğrudan sunulabilmesi için fallback:
urlpatterns += [
    re_path(r'^static/(?P<path>.*)$', serve, {
        'document_root': settings.STATIC_ROOT if (hasattr(settings, 'STATIC_ROOT') and settings.STATIC_ROOT and settings.STATIC_ROOT.exists()) else settings.STATICFILES_DIRS[0]
    }),
]
