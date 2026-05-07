<?php

use App\Http\Controllers\AppointmentController;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\PlanController;
use App\Http\Controllers\SpecialityController;
use App\Http\Controllers\ProviderController;
use App\Http\Controllers\ClientController;
use App\Http\Controllers\CountriesController;
use App\Http\Controllers\HomeController;
use App\Http\Controllers\RoleController;
use App\Http\Controllers\PatientsController;


Route::get('/login', [AuthController::class, 'showLoginForm'])->name('login.show');
Route::post('/login', [AuthController::class, 'login'])->name('login');
Route::post('/logout', [AuthController::class, 'logout'])->name('logout');
Route::get('/register', [AuthController::class, 'showRegistrationForm'])->name('register.show');
Route::post('/register', [AuthController::class, 'register'])->name('register');
Route::get('/forgot-password', [AuthController::class, 'showForgotPasswordForm'])->name('password.request');
Route::post('/password/reset/request', [AuthController::class, 'sendOtp'])->name('password.reset.request');
Route::post('/password/reset/verify', [AuthController::class, 'verifyOtp'])->name('password.reset.verify');


// HOME SITE ROUTES 

Route::get('/', [HomeController::class, 'index'])->name('index');
Route::get('/providerregisteration', [HomeController::class, 'providerregisteration'])->name('providerregisteration');
Route::post('/providerstore', [HomeController::class, 'providerstore'])->name('apply.provider.store');
Route::get('/providersuccess', [HomeController::class, 'providersuccess'])->name('provider.success');


Route::resource('roles', RoleController::class);

// PLANS ROUTES
Route::resource('plans', PlanController::class);
// SPECIALLITY ROUTES
Route::resource('specialities', SpecialityController::class);
// COUNTRIES ROUTES
Route::resource('countries', CountriesController::class);
// PROVIDER ROUTES
Route::resource('providers', ProviderController::class);
// PAITIENTS ROUTES
Route::resource('patients', PatientsController::class);

Route::resource('appointments', AppointmentController::class);

Route::post('/appointment-approval/{id}', [AppointmentController::class, 'approval'])->name('appointment.approval');

Route::get('/dashboard', function () {
    return view('dashboards.dashboard');
})->name('dashboard');


Route::get('/clientside/profile', [ClientController::class, 'profile'])->name('client.profile');
Route::get('/clientside/index', [ClientController::class, 'index'])->name('client.index');
Route::get('/clientside/plan', [ClientController::class, 'plan'])->name('client.plan');

// Doctor On Call (React SPA) — mirrors `flutter_emr` app shell.
Route::view('/app', 'react_app')->name('docsoncalls.app');
Route::view('/app/{path}', 'react_app')->where('path', '.*');
