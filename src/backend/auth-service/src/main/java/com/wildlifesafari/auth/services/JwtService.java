package com.wildlifesafari.auth.services;

import com.wildlifesafari.auth.config.JwtConfig;
import com.wildlifesafari.auth.models.User;
import io.jsonwebtoken.Claims; // io.jsonwebtoken:jjwt-api:0.11.5
import io.jsonwebtoken.Jwts; // io.jsonwebtoken:jjwt-api:0.11.5
import io.jsonwebtoken.SignatureAlgorithm; // io.jsonwebtoken:jjwt-api:0.11.5
import io.jsonwebtoken.security.Keys; // io.jsonwebtoken:jjwt-api:0.11.5
import org.springframework.stereotype.Service; // org.springframework:spring-context:5.3.0
import org.springframework.cache.annotation.Cache; // org.springframework:spring-cache:5.3.0
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;

import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.SecureRandom;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.logging.Logger;

/**
 * Service class responsible for JWT token operations with enhanced security features.
 * Implements secure token generation, validation, and management with role-based claims.
 * 
 * @version 1.0
 * @since 2024-01-01
 */
@Service
public class JwtService {
    
    private static final Logger logger = Logger.getLogger(JwtService.class.getName());
    private static final String TOKEN_PREFIX = "Bearer ";
    private static final String FINGERPRINT_CLAIM = "fgp";
    private static final String ROLE_CLAIM = "role";
    private static final String USER_ID_CLAIM = "uid";
    private static final SecureRandom secureRandom = new SecureRandom();
    
    private final JwtConfig jwtConfig;
    private final Map<String, String> tokenBlacklist;
    
    /**
     * Initializes the JWT service with required configuration
     * @param jwtConfig JWT configuration settings
     */
    public JwtService(JwtConfig jwtConfig) {
        this.jwtConfig = jwtConfig;
        this.tokenBlacklist = new HashMap<>();
        validateConfiguration();
    }
    
    /**
     * Generates a secure JWT token with role-based claims and fingerprinting
     * @param user User entity for token generation
     * @return Generated JWT token
     * @throws IllegalArgumentException if user data is invalid
     */
    public String generateToken(User user) {
        validateUser(user);
        
        Date now = new Date();
        Date expiration = new Date(now.getTime() + (jwtConfig.getTokenValidityInSeconds() * 1000));
        String fingerprint = generateTokenFingerprint();
        
        try {
            PrivateKey privateKey = loadPrivateKey(jwtConfig.getSecretKey());
            
            String token = Jwts.builder()
                .setId(UUID.randomUUID().toString())
                .setSubject(user.getEmail())
                .setIssuer(jwtConfig.getIssuer())
                .setAudience(jwtConfig.getAudience())
                .setIssuedAt(now)
                .setExpiration(expiration)
                .claim(USER_ID_CLAIM, user.getId().toString())
                .claim(ROLE_CLAIM, user.getRole().name())
                .claim(FINGERPRINT_CLAIM, fingerprint)
                .signWith(privateKey, SignatureAlgorithm.RS256)
                .compact();
                
            logger.fine("Generated JWT token for user: " + user.getEmail());
            return TOKEN_PREFIX + token;
            
        } catch (Exception e) {
            logger.severe("Failed to generate JWT token: " + e.getMessage());
            throw new RuntimeException("Token generation failed", e);
        }
    }
    
    /**
     * Validates JWT token with enhanced security checks
     * @param token JWT token to validate
     * @return true if token is valid
     */
    @Cacheable(value = "tokenValidationCache", key = "#token")
    public boolean validateToken(String token) {
        if (token == null || !token.startsWith(TOKEN_PREFIX)) {
            return false;
        }
        
        String actualToken = token.substring(TOKEN_PREFIX.length());
        
        try {
            PublicKey publicKey = loadPublicKey(jwtConfig.getPublicKey());
            
            Claims claims = Jwts.parserBuilder()
                .setSigningKey(publicKey)
                .requireIssuer(jwtConfig.getIssuer())
                .requireAudience(jwtConfig.getAudience())
                .build()
                .parseClaimsJws(actualToken)
                .getBody();
                
            return !isTokenBlacklisted(claims.getId()) &&
                   claims.getExpiration().after(new Date()) &&
                   claims.containsKey(FINGERPRINT_CLAIM);
                   
        } catch (Exception e) {
            logger.warning("Token validation failed: " + e.getMessage());
            return false;
        }
    }
    
    /**
     * Refreshes an existing token while invalidating the old one
     * @param oldToken Current valid token
     * @param user User entity for new token
     * @return New JWT token
     * @throws IllegalArgumentException if old token is invalid
     */
    @CacheEvict(value = "tokenValidationCache", key = "#oldToken")
    public String refreshToken(String oldToken, User user) {
        if (!validateToken(oldToken)) {
            throw new IllegalArgumentException("Invalid token for refresh");
        }
        
        try {
            Claims oldClaims = extractClaims(oldToken);
            blacklistToken(oldClaims.getId());
            return generateToken(user);
            
        } catch (Exception e) {
            logger.severe("Token refresh failed: " + e.getMessage());
            throw new RuntimeException("Token refresh failed", e);
        }
    }
    
    /**
     * Invalidates a token by adding it to the blacklist
     * @param token Token to invalidate
     */
    @CacheEvict(value = "tokenValidationCache", key = "#token")
    public void invalidateToken(String token) {
        try {
            Claims claims = extractClaims(token);
            blacklistToken(claims.getId());
            logger.info("Token invalidated: " + claims.getId());
        } catch (Exception e) {
            logger.warning("Token invalidation failed: " + e.getMessage());
        }
    }
    
    private void validateUser(User user) {
        if (user == null || user.getId() == null || user.getEmail() == null || user.getRole() == null) {
            throw new IllegalArgumentException("Invalid user data for token generation");
        }
    }
    
    private String generateTokenFingerprint() {
        byte[] randomBytes = new byte[32];
        secureRandom.nextBytes(randomBytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(randomBytes);
    }
    
    private PrivateKey loadPrivateKey(String base64PrivateKey) throws Exception {
        byte[] privateKeyBytes = Base64.getDecoder().decode(base64PrivateKey);
        PKCS8EncodedKeySpec keySpec = new PKCS8EncodedKeySpec(privateKeyBytes);
        KeyFactory keyFactory = KeyFactory.getInstance("RSA");
        return keyFactory.generatePrivate(keySpec);
    }
    
    private PublicKey loadPublicKey(String base64PublicKey) throws Exception {
        byte[] publicKeyBytes = Base64.getDecoder().decode(base64PublicKey);
        X509EncodedKeySpec keySpec = new X509EncodedKeySpec(publicKeyBytes);
        KeyFactory keyFactory = KeyFactory.getInstance("RSA");
        return keyFactory.generatePublic(keySpec);
    }
    
    private Claims extractClaims(String token) throws Exception {
        if (token.startsWith(TOKEN_PREFIX)) {
            token = token.substring(TOKEN_PREFIX.length());
        }
        
        PublicKey publicKey = loadPublicKey(jwtConfig.getPublicKey());
        return Jwts.parserBuilder()
            .setSigningKey(publicKey)
            .build()
            .parseClaimsJws(token)
            .getBody();
    }
    
    private void blacklistToken(String tokenId) {
        tokenBlacklist.put(tokenId, new Date().toString());
    }
    
    private boolean isTokenBlacklisted(String tokenId) {
        return tokenBlacklist.containsKey(tokenId);
    }
    
    private void validateConfiguration() {
        if (!jwtConfig.validateConfiguration()) {
            throw new IllegalStateException("Invalid JWT configuration");
        }
    }
}