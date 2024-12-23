package com.wildlifesafari.auth;

import com.auth0.spring.security.api.EnableAuth0; // com.auth0:auth0-spring-security-api:1.0.0
import com.wildlifesafari.auth.config.SecurityConfig;
import com.wildlifesafari.auth.config.JwtConfig;
import io.micrometer.core.instrument.MeterRegistry; // io.micrometer:micrometer-core:1.9.0
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.cloud.client.discovery.EnableDiscoveryClient;
import org.springframework.context.annotation.Bean;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.boot.actuate.autoconfigure.security.servlet.ManagementWebSecurityAutoConfiguration;
import org.springframework.cache.annotation.EnableCaching;

import java.util.logging.Logger;

/**
 * Main Spring Boot application class for the Wildlife Safari Pokédex authentication service.
 * Implements comprehensive security features including OAuth2/OIDC, JWT management,
 * and security monitoring capabilities.
 *
 * @version 1.0
 * @since 2024-01-01
 */
@SpringBootApplication(exclude = {ManagementWebSecurityAutoConfiguration.class})
@EnableDiscoveryClient
@EnableAuth0
@EnableConfigurationProperties({JwtConfig.class})
@EnableCaching
public class AuthServiceApplication {

    private static final Logger logger = Logger.getLogger(AuthServiceApplication.class.getName());

    /**
     * Main entry point for the authentication service
     * @param args Command line arguments
     */
    public static void main(String[] args) {
        logger.info("Initializing Wildlife Safari Pokédex Authentication Service");
        SpringApplication.run(AuthServiceApplication.class, args);
    }

    /**
     * Configures the password encoder for secure credential storage
     * @return BCryptPasswordEncoder instance
     */
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12); // Using strength 12 for production security
    }

    /**
     * Configures security metrics collector for monitoring
     * @param registry Metrics registry
     * @return SecurityMetricsCollector instance
     */
    @Bean
    public SecurityMetricsCollector securityMetricsCollector(MeterRegistry registry) {
        return new SecurityMetricsCollector(registry);
    }

    /**
     * Configures security event listener for audit logging
     * @return SecurityEventListener instance
     */
    @Bean
    public SecurityEventListener securityEventListener() {
        return new SecurityEventListener();
    }

    /**
     * Configures audit logger for security events
     * @return AuditLogger instance
     */
    @Bean
    public AuditLogger auditLogger() {
        return new AuditLogger();
    }

    /**
     * Inner class for collecting security-related metrics
     */
    private static class SecurityMetricsCollector {
        private final MeterRegistry registry;

        public SecurityMetricsCollector(MeterRegistry registry) {
            this.registry = registry;
            initializeMetrics();
        }

        private void initializeMetrics() {
            registry.gauge("auth.active.sessions", 0);
            registry.counter("auth.login.attempts");
            registry.counter("auth.login.failures");
            registry.timer("auth.token.validation");
            registry.counter("auth.token.revocations");
        }
    }

    /**
     * Inner class for handling security events
     */
    private static class SecurityEventListener {
        private static final Logger eventLogger = Logger.getLogger(SecurityEventListener.class.getName());

        public void onLoginSuccess(String username) {
            eventLogger.info("Successful login for user: " + username);
        }

        public void onLoginFailure(String username, String reason) {
            eventLogger.warning("Login failed for user: " + username + ", reason: " + reason);
        }

        public void onTokenRevocation(String tokenId) {
            eventLogger.info("Token revoked: " + tokenId);
        }
    }

    /**
     * Inner class for security audit logging
     */
    private static class AuditLogger {
        private static final Logger auditLogger = Logger.getLogger("SecurityAudit");

        public void logSecurityEvent(String event, String details) {
            auditLogger.info(String.format("[SECURITY_AUDIT] %s - %s", event, details));
        }

        public void logSecurityViolation(String violation, String details) {
            auditLogger.warning(String.format("[SECURITY_VIOLATION] %s - %s", violation, details));
        }
    }
}