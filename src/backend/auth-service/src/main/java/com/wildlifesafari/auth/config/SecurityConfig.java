package com.wildlifesafari.auth.config;

import com.wildlifesafari.auth.services.JwtService;
import com.wildlifesafari.auth.services.AuthService;
import io.github.bucket4j.Bucket4j; // io.github.bucket4j:bucket4j-core:7.6.0
import io.github.bucket4j.Bandwidth;
import io.github.bucket4j.Refill;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.security.web.csrf.CookieCsrfTokenRepository;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.security.oauth2.client.web.OAuth2LoginAuthenticationFilter;
import org.springframework.security.web.header.writers.ReferrerPolicyHeaderWriter;
import org.springframework.http.HttpMethod;

import java.time.Duration;
import java.util.Arrays;
import java.util.List;

/**
 * Enhanced Spring Security configuration implementing comprehensive security measures
 * for the Wildlife Safari Pokédex authentication service.
 * 
 * @version 1.0
 * @since 2024-01-01
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    private final JwtService jwtService;
    private final AuthService authService;
    private final Bucket4j.Builder bucketBuilder;
    
    private static final String[] PUBLIC_ENDPOINTS = {
        "/api/v1/auth/login",
        "/api/v1/auth/register",
        "/api/v1/auth/oauth2/**",
        "/actuator/health"
    };

    /**
     * Initializes security configuration with required services
     */
    public SecurityConfig(JwtService jwtService, AuthService authService) {
        this.jwtService = jwtService;
        this.authService = authService;
        this.bucketBuilder = Bucket4j.builder()
            .addLimit(Bandwidth.classic(100, Refill.intervally(100, Duration.ofMinutes(1))));
    }

    /**
     * Configures the security filter chain with comprehensive security measures
     */
    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        return http
            // Basic Security Configuration
            .csrf(csrf -> csrf
                .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
                .ignoringAntMatchers(PUBLIC_ENDPOINTS))
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .sessionManagement(session -> session
                .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            
            // Security Headers
            .headers(headers -> headers
                .frameOptions().deny()
                .xssProtection().block(true)
                .contentSecurityPolicy("default-src 'self'; frame-ancestors 'none'")
                .referrerPolicy(ReferrerPolicyHeaderWriter.ReferrerPolicy.STRICT_ORIGIN_WHEN_CROSS_ORIGIN)
                .permissionsPolicy().policy("camera=(), microphone=(), geolocation=()")
                .httpStrictTransportSecurity().maxAgeInSeconds(31536000))
            
            // Authorization Rules
            .authorizeRequests(authorize -> authorize
                .antMatchers(PUBLIC_ENDPOINTS).permitAll()
                .antMatchers(HttpMethod.GET, "/api/v1/species/**").hasAnyRole("BASIC_USER", "RESEARCHER", "MODERATOR", "ADMINISTRATOR")
                .antMatchers(HttpMethod.POST, "/api/v1/discoveries/**").hasAnyRole("BASIC_USER", "RESEARCHER", "MODERATOR", "ADMINISTRATOR")
                .antMatchers(HttpMethod.PUT, "/api/v1/discoveries/**").hasAnyRole("MODERATOR", "ADMINISTRATOR")
                .antMatchers("/api/v1/admin/**").hasRole("ADMINISTRATOR")
                .anyRequest().authenticated())
            
            // OAuth2 Configuration
            .oauth2Login(oauth2 -> oauth2
                .authorizationEndpoint().baseUri("/api/v1/auth/oauth2/authorization")
                .and()
                .redirectionEndpoint().baseUri("/api/v1/auth/oauth2/callback/*")
                .and()
                .userInfoEndpoint().userService(authService::handleOAuth2Authentication)
                .and()
                .successHandler((request, response, authentication) -> {
                    // Custom success handler implementation
                })
                .failureHandler((request, response, exception) -> {
                    // Custom failure handler implementation
                }))
            
            // Custom Filters
            .addFilterBefore(new JwtAuthenticationFilter(jwtService, authService), 
                           UsernamePasswordAuthenticationFilter.class)
            .addFilterAfter(new RateLimitFilter(bucketBuilder), 
                          OAuth2LoginAuthenticationFilter.class)
            
            // Exception Handling
            .exceptionHandling(exceptions -> exceptions
                .authenticationEntryPoint((request, response, authException) -> {
                    response.setStatus(401);
                    response.getWriter().write("Unauthorized");
                })
                .accessDeniedHandler((request, response, accessDeniedException) -> {
                    response.setStatus(403);
                    response.getWriter().write("Access Denied");
                }))
            
            .build();
    }

    /**
     * Configures CORS settings with strict security measures
     */
    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        configuration.setAllowedOrigins(List.of("https://wildlifesafari.com", "https://api.wildlifesafari.com"));
        configuration.setAllowedMethods(Arrays.asList("GET", "POST", "PUT", "DELETE", "OPTIONS"));
        configuration.setAllowedHeaders(Arrays.asList("Authorization", "Content-Type", "X-Requested-With", "X-XSRF-TOKEN"));
        configuration.setExposedHeaders(Arrays.asList("X-XSRF-TOKEN"));
        configuration.setAllowCredentials(true);
        configuration.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/**", configuration);
        return source;
    }
}