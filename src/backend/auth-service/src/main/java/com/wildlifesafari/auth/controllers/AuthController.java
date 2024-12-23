package com.wildlifesafari.auth.controllers;

import com.wildlifesafari.auth.models.User;
import com.wildlifesafari.auth.services.AuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeType;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;
import org.springframework.security.core.AuthenticationException;

import javax.validation.Valid;
import javax.validation.constraints.NotNull;
import java.util.Optional;
import java.util.logging.Logger;

/**
 * REST controller handling authentication endpoints for the Wildlife Safari Pokédex application.
 * Implements comprehensive security features including OAuth2, biometric authentication,
 * and role-based access control.
 *
 * @version 1.0
 * @since 2024-01-01
 */
@RestController
@RequestMapping("/api/v1/auth")
@Validated
@Tag(name = "Authentication", description = "Authentication management endpoints")
@SecurityScheme(
    name = "bearerAuth",
    type = SecuritySchemeType.HTTP,
    scheme = "bearer",
    bearerFormat = "JWT"
)
public class AuthController {

    private static final Logger logger = Logger.getLogger(AuthController.class.getName());
    private static final String FINGERPRINT_HEADER = "X-Fingerprint";
    private static final String TOKEN_HEADER = "Authorization";

    private final AuthService authService;

    /**
     * Initializes the authentication controller with required dependencies
     * @param authService Authentication service instance
     */
    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    /**
     * Handles user login with enhanced security features
     * @param request Login credentials
     * @return JWT token with security headers
     */
    @PostMapping("/login")
    @Operation(
        summary = "Authenticate user",
        description = "Authenticates user credentials and returns JWT token"
    )
    @ApiResponse(responseCode = "200", description = "Authentication successful")
    @ApiResponse(responseCode = "401", description = "Authentication failed")
    @ApiResponse(responseCode = "429", description = "Too many attempts")
    public ResponseEntity<AuthResponse> login(@Valid @RequestBody LoginRequest request) {
        try {
            AuthenticationResponse authResponse = authService.authenticate(
                request.getEmail(),
                request.getPassword(),
                Optional.ofNullable(request.getBiometricData())
            );

            HttpHeaders headers = new HttpHeaders();
            headers.add(TOKEN_HEADER, authResponse.getToken());
            headers.add(FINGERPRINT_HEADER, authResponse.getFingerprint());
            headers.add("X-Rate-Limit-Remaining", "60");

            return ResponseEntity.ok()
                .headers(headers)
                .body(new AuthResponse(
                    authResponse.getToken(),
                    authResponse.getRole(),
                    authResponse.getExpiresIn()
                ));

        } catch (AuthenticationException e) {
            logger.warning("Authentication failed for user: " + request.getEmail());
            throw new AuthenticationFailedException("Invalid credentials");
        }
    }

    /**
     * Handles OAuth2 authentication flow
     * @param request OAuth2 authentication request
     * @return JWT token with OAuth2 claims
     */
    @PostMapping("/oauth2/authenticate")
    @Operation(
        summary = "OAuth2 authentication",
        description = "Handles OAuth2 authentication flow"
    )
    public ResponseEntity<AuthResponse> oauth2Authenticate(
            @Valid @RequestBody OAuth2AuthRequest request) {
        try {
            AuthenticationResponse authResponse = authService.authenticateOAuth2(
                request.getProvider(),
                request.getCode()
            );

            HttpHeaders headers = new HttpHeaders();
            headers.add(TOKEN_HEADER, authResponse.getToken());
            headers.add(FINGERPRINT_HEADER, authResponse.getFingerprint());

            return ResponseEntity.ok()
                .headers(headers)
                .body(new AuthResponse(
                    authResponse.getToken(),
                    authResponse.getRole(),
                    authResponse.getExpiresIn()
                ));

        } catch (Exception e) {
            logger.severe("OAuth2 authentication failed: " + e.getMessage());
            throw new OAuth2AuthenticationException("OAuth2 authentication failed");
        }
    }

    /**
     * Handles biometric authentication
     * @param request Biometric authentication data
     * @return Authentication response with biometric validation
     */
    @PostMapping("/biometric/authenticate")
    @Operation(
        summary = "Biometric authentication",
        description = "Authenticates using biometric data"
    )
    public ResponseEntity<AuthResponse> biometricAuthenticate(
            @Valid @RequestBody BiometricAuthRequest request) {
        try {
            AuthenticationResponse authResponse = authService.authenticateBiometric(
                request.getBiometricData(),
                request.getDeviceId()
            );

            HttpHeaders headers = new HttpHeaders();
            headers.add(TOKEN_HEADER, authResponse.getToken());
            headers.add(FINGERPRINT_HEADER, authResponse.getFingerprint());

            return ResponseEntity.ok()
                .headers(headers)
                .body(new AuthResponse(
                    authResponse.getToken(),
                    authResponse.getRole(),
                    authResponse.getExpiresIn()
                ));

        } catch (Exception e) {
            logger.severe("Biometric authentication failed: " + e.getMessage());
            throw new BiometricAuthenticationException("Biometric authentication failed");
        }
    }

    /**
     * Refreshes an existing valid JWT token
     * @param request Token refresh request
     * @return New JWT token
     */
    @PostMapping("/token/refresh")
    @Operation(
        summary = "Refresh token",
        description = "Refreshes a valid JWT token"
    )
    @SecurityRequirement(name = "bearerAuth")
    public ResponseEntity<AuthResponse> refreshToken(
            @RequestHeader(TOKEN_HEADER) String token,
            @RequestHeader(FINGERPRINT_HEADER) String fingerprint) {
        try {
            if (!authService.validateToken(token, fingerprint)) {
                throw new InvalidTokenException("Invalid token for refresh");
            }

            AuthenticationResponse authResponse = authService.refreshToken(token);

            HttpHeaders headers = new HttpHeaders();
            headers.add(TOKEN_HEADER, authResponse.getToken());
            headers.add(FINGERPRINT_HEADER, authResponse.getFingerprint());

            return ResponseEntity.ok()
                .headers(headers)
                .body(new AuthResponse(
                    authResponse.getToken(),
                    authResponse.getRole(),
                    authResponse.getExpiresIn()
                ));

        } catch (Exception e) {
            logger.warning("Token refresh failed: " + e.getMessage());
            throw new TokenRefreshException("Token refresh failed");
        }
    }

    /**
     * Invalidates the current session
     * @param token Current JWT token
     * @return Logout confirmation
     */
    @PostMapping("/logout")
    @Operation(
        summary = "Logout",
        description = "Invalidates current session"
    )
    @SecurityRequirement(name = "bearerAuth")
    public ResponseEntity<Void> logout(@RequestHeader(TOKEN_HEADER) String token) {
        try {
            authService.logout(token);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            logger.warning("Logout failed: " + e.getMessage());
            throw new LogoutException("Logout failed");
        }
    }

    /**
     * Validates token status
     * @param token JWT token to validate
     * @return Token validation status
     */
    @GetMapping("/token/validate")
    @Operation(
        summary = "Validate token",
        description = "Checks if token is valid"
    )
    public ResponseEntity<TokenValidationResponse> validateToken(
            @RequestHeader(TOKEN_HEADER) String token,
            @RequestHeader(FINGERPRINT_HEADER) String fingerprint) {
        boolean isValid = authService.validateToken(token, fingerprint);
        return ResponseEntity.ok(new TokenValidationResponse(isValid));
    }
}