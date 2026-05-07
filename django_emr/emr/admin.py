from django.contrib import admin

from .models import (
    Appointment,
    Country,
    Feedback,
    NutritionEntry,
    Patient,
    Plan,
    Provider,
    Speciality,
)

admin.site.register(Country)
admin.site.register(Speciality)
admin.site.register(Plan)
admin.site.register(Patient)
admin.site.register(Provider)
admin.site.register(Appointment)
admin.site.register(Feedback)
admin.site.register(NutritionEntry)
