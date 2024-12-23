package com.wildlifesafari.auth.services;

import com.google.common.util.concurrent.RateLimiter;
import com.wildlifesafari.auth.models.User;
import com.wildlifesafari.auth.repositories.UserRepository;
import com.wildlifesafari.auth.security.SecurityAuditLogger;
import org.springframework.cache.Cache;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.oauth2.core.OAuth2AuthenticationToken;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

/**
 * Enhanced authentication service with comprehensive security features including
 * biometric authentication, token fingerprinting, and security audit logging.
 * 
 * @version 1.0
 * @since 2024-01-01
 */
@Service
public class AuthService {

    private static final int MAX_LOGIN_ATTEMPTS = 5;
    private static final long LOCKOUT_DURATION_MINUTES = 30;
    private static final double REQUESTS_PER_SECOND = 10.0;

    private final UserRepository userRepository;
    private final JwtService jwtService;
    private final BCryptPasswordEncoder passwordEncoder;
    private final RateLimiter rateLimiter;
    private final SecurityAuditLogger securityAuditLogger;
    private final Cache tokenCache;
    private final Map<String, Integer> loginAttempts;
    private final Map<String, LocalDateTime> lockoutTimestamps;

    /**
     * Initializes the authentication service with required dependencies
     */
    public AuthService(
            UserRepository userRepository,
            JwtService jwtService,
            BCryptPasswordEncoder passwordEncoder,
            SecurityAuditLogger securityAuditLogger,
            Cache tokenCache) {
        this.userRepository = userRepository;
        this.jwtService = jwtService;
        this.passwordEncoder = passwordEncoder;
        this.securityAuditLogger = securityAuditLogger;
        this.tokenCache = tokenCache;
        this.rateLimiter = RateLimiter.create(REQUESTS_PER_SECOND);
        this.loginAttempts = new HashMap<>();
        this.lockoutTimestamps = new HashMap<>();
    }

    /**
     * Authenticates a user with enhanced security checks and rate limiting
     * 
     * @param email User email
     * @param password User password
     * @param biometricData Optional biometric data
     * @return AuthenticationResponse containing JWT token and fingerprint
     * @throws AuthenticationException if authentication fails
     */
    public AuthenticationResponse authenticate(String email, String password, Optional<BiometricData> biometricData) {
        if (!rateLimiter.tryAcquire(1, TimeUnit.SECONDS)) {
            securityAuditLogger.logRateLimitExceeded(email);
            throw new AuthenticationException("Rate limit exceeded");
        }

        checkLockoutStatus(email);

        try {
            Optional<User> userOpt = userRepository.findByEmailAndEnabled(email, true);
            if (userOpt.isEmpty()) {
                handleFailedLogin(email);
                securityAuditLogger.logFailedLogin(email, "User not found or disabled");
                throw new AuthenticationException("Invalid credentials");
            }

            User user = userOpt.get();
            validateUserStatus(user);
            validateCredentials(user, password);
            validateBiometricData(user, biometricData);

            // Reset login attempts on successful authentication
            loginAttempts.remove(email);

            // Generate token with fingerprint
            String fingerprint = jwtService.generateFingerprint();
            String token = jwtService.generateToken(user);
            
            // Update last login and audit
            user.updateLastLogin("SYSTEM");
            userRepository.save(user);
            securityAuditLogger.logSuccessfulLogin(user.getId(), user.getEmail());

            return new AuthenticationResponse(token, fingerprint, user.getRole());

        } catch (Exception e) {
            securityAuditLogger.logAuthenticationError(email, e.getMessage());
            throw new AuthenticationException("Authentication failed: " + e.getMessage());
        }
    }

    /**
     * Validates token with fingerprint verification
     * 
     * @param token JWT token
     * @param fingerprint Token fingerprint
     * @return true if token is valid
     */
    public boolean validateTokenWithFingerprint(String token, String fingerprint) {
        try {
            if (!jwtService.validateToken(token)) {
                securityAuditLogger.logInvalidToken(token);
                return false;
            }

            String cachedFingerprint = tokenCache.get(token, String.class);
            if (cachedFingerprint == null || !cachedFingerprint.equals(fingerprint)) {
                securityAuditLogger.logFingerprintMismatch(token);
                return false;
            }

            return true;
        } catch (Exception e) {
            securityAuditLogger.logTokenValidationError(token, e.getMessage());
            return false;
        }
    }

    /**
     * Handles OAuth2 authentication with role mapping
     * 
     * @param oauth2Token OAuth2 authentication token
     * @return AuthenticationResponse with JWT token
     */
    public AuthenticationResponse handleOAuth2Authentication(OAuth2AuthenticationToken oauth2Token) {
        String email = oauth2Token.getPrincipal().getAttribute("email");
        
        User user = userRepository.findByEmail(email)
            .orElseGet(() -> createOAuth2User(oauth2Token));

        String fingerprint = jwtService.generateFingerprint();
        String token = jwtService.generateToken(user);

        user.updateLastLogin("OAUTH2");
        userRepository.save(user);
        securityAuditLogger.logOAuth2Login(user.getId(), email);

        return new AuthenticationResponse(token, fingerprint, user.getRole());
    }

    /**
     * Invalidates user session and logs out
     * 
     * @param token JWT token to invalidate
     */
    public void logout(String token) {
        try {
            UUID userId = jwtService.getUserIdFromToken(token);
            jwtService.invalidateToken(token);
            tokenCache.evict(token);
            securityAuditLogger.logLogout(userId);
        } catch (Exception e) {
            securityAuditLogger.logLogoutError(token, e.getMessage());
        }
    }

    private void validateUserStatus(User user) {
        if (user.getStatus() != User.AccountStatus.ACTIVE) {
            securityAuditLogger.logInactiveAccountAttempt(user.getId());
            throw new AuthenticationException("Account is not active");
        }
    }

    private void validateCredentials(User user, String password) {
        if (!passwordEncoder.matches(password, user.getPassword())) {
            handleFailedLogin(user.getEmail());
            securityAuditLogger.logInvalidPassword(user.getId());
            throw new AuthenticationException("Invalid credentials");
        }
    }

    private void validateBiometricData(User user, Optional<BiometricData> biometricData) {
        if (user.isBiometricEnabled() && biometricData.isEmpty()) {
            securityAuditLogger.logMissingBiometric(user.getId());
            throw new AuthenticationException("Biometric authentication required");
        }
    }

    private void handleFailedLogin(String email) {
        int attempts = loginAttempts.getOrDefault(email, 0) + 1;
        loginAttempts.put(email, attempts);

        if (attempts >= MAX_LOGIN_ATTEMPTS) {
            lockoutTimestamps.put(email, LocalDateTime.now());
            securityAuditLogger.logAccountLockout(email);
        }
    }

    private void checkLockoutStatus(String email) {
        LocalDateTime lockoutTime = lockoutTimestamps.get(email);
        if (lockoutTime != null) {
            if (LocalDateTime.now().isBefore(lockoutTime.plusMinutes(LOCKOUT_DURATION_MINUTES))) {
                throw new AuthenticationException("Account temporarily locked");
            } else {
                lockoutTimestamps.remove(email);
                loginAttempts.remove(email);
            }
        }
    }

    private User createOAuth2User(OAuth2AuthenticationToken oauth2Token) {
        User user = new User();
        user.setEmail(oauth2Token.getPrincipal().getAttribute("email"));
        user.setRole(User.UserRole.BASIC_USER);
        user.setStatus(User.AccountStatus.ACTIVE);
        user.setEnabled(true);
        return userRepository.save(user);
    }
}