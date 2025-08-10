<?php

use Illuminate\Foundation\Application;
use Illuminate\Http\Request;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware) {
        // Trust Render's reverse proxy so HTTPS scheme is honored via X-Forwarded-* headers
        $middleware->trustProxies(at: '*');

        $middleware->alias([
            'pg.login_email' => \App\Http\Middleware\SetPgLoginEmail::class,
        ]);

        $middleware->web(append: [
            \App\Http\Middleware\SetPgUserContext::class,
            \App\Http\Middleware\HandleInertiaRequests::class,
            \Illuminate\Http\Middleware\AddLinkHeadersForPreloadedAssets::class,
        ]);

        //
    })
    ->withExceptions(function (Exceptions $exceptions) {
        //
    })->create();
