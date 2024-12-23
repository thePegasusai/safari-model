package com.wildlifesafari.auth.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.validation.annotation.Validated;
import javax.validation.constraints.NotNull;
import javax.validation.constraints.Min;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;
import java.util.logging.Logger;
import javax.annotation.PostConstruct;

/**
 * JWT Configuration class for Wildlife Safari Pokédex authentication system.
 * Implements secure token generation with RS256 signing and automated key rotation.
 * 
 * @version 1.0
 * @since 2024-01-01
 */
@Configuration
@ConfigurationProperties(prefix = "jwt")
@Validated
public class JwtConfig {
    
    private static final Logger logger = Logger.getLogger(JwtConfig.class.getName());
    
    @NotNull
    private String secretKey;
    
    @NotNull
    private String publicKey;
    
    @NotNull
    @Min(300) // Minimum 5 minutes
    private long tokenValidityInSeconds;
    
    @NotNull
    private String issuer;
    
    @NotNull
    private String audience;
    
    @NotNull
    private String algorithm;
    
    private boolean keyRotationEnabled;
    
    @Min(1)
    private long keyRotationPeriodInDays;
    
    @Min(128)
    private int minTokenLength;
    
    private long lastKeyRotationTimestamp;

    /**
     * Initializes JWT configuration with secure defaults
     */
    public JwtConfig() {
        this.algorithm = "RS256";
        this.tokenValidityInSeconds = 604800L; // 7 days
        this.keyRotationEnabled = true;
        this.keyRotationPeriodInDays = 7L;
        this.minTokenLength = 128;
        this.lastKeyRotationTimestamp = System.currentTimeMillis();
    }

    @PostConstruct
    public void init() {
        if (secretKey == null || publicKey == null) {
            try {
                generateNewKeyPair();
            } catch (NoSuchAlgorithmException e) {
                logger.severe("Failed to initialize key pair: " + e.getMessage());
                throw new RuntimeException("JWT key initialization failed", e);
            }
        }
        validateConfiguration();
    }

    /**
     * Retrieves the JWT signing key in a secure manner
     * @return Base64 encoded private key
     */
    public String getSecretKey() {
        if (secretKey == null) {
            throw new IllegalStateException("JWT signing key not initialized");
        }
        checkKeyRotation();
        return secretKey;
    }

    /**
     * Retrieves the JWT public key for token verification
     * @return Base64 encoded public key
     */
    public String getPublicKey() {
        if (publicKey == null) {
            throw new IllegalStateException("JWT public key not initialized");
        }
        return publicKey;
    }

    /**
     * Rotates JWT key pair based on configured rotation period
     */
    public void rotateKeys() {
        try {
            generateNewKeyPair();
            this.lastKeyRotationTimestamp = System.currentTimeMillis();
            logger.info("JWT key pair rotated successfully");
        } catch (NoSuchAlgorithmException e) {
            logger.severe("Failed to rotate keys: " + e.getMessage());
            throw new RuntimeException("Key rotation failed", e);
        }
    }

    /**
     * Validates JWT configuration settings
     * @return true if configuration is valid
     */
    public boolean validateConfiguration() {
        if (tokenValidityInSeconds < 300) {
            throw new IllegalStateException("Token validity period too short");
        }
        if (!algorithm.equals("RS256")) {
            throw new IllegalStateException("Only RS256 algorithm is supported");
        }
        if (minTokenLength < 128) {
            throw new IllegalStateException("Minimum token length must be at least 128 characters");
        }
        return true;
    }

    private void generateNewKeyPair() throws NoSuchAlgorithmException {
        KeyPairGenerator keyGen = KeyPairGenerator.getInstance("RSA");
        keyGen.initialize(2048); // Use 2048 bits for production security
        KeyPair keyPair = keyGen.generateKeyPair();
        
        this.secretKey = Base64.getEncoder().encodeToString(keyPair.getPrivate().getEncoded());
        this.publicKey = Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());
    }

    private void checkKeyRotation() {
        if (keyRotationEnabled) {
            long currentTime = System.currentTimeMillis();
            long rotationPeriodMillis = keyRotationPeriodInDays * 24 * 60 * 60 * 1000;
            
            if (currentTime - lastKeyRotationTimestamp > rotationPeriodMillis) {
                rotateKeys();
            }
        }
    }

    // Getters and Setters
    public void setSecretKey(String secretKey) {
        this.secretKey = secretKey;
    }

    public void setPublicKey(String publicKey) {
        this.publicKey = publicKey;
    }

    public long getTokenValidityInSeconds() {
        return tokenValidityInSeconds;
    }

    public void setTokenValidityInSeconds(long tokenValidityInSeconds) {
        this.tokenValidityInSeconds = tokenValidityInSeconds;
    }

    public String getIssuer() {
        return issuer;
    }

    public void setIssuer(String issuer) {
        this.issuer = issuer;
    }

    public String getAudience() {
        return audience;
    }

    public void setAudience(String audience) {
        this.audience = audience;
    }

    public String getAlgorithm() {
        return algorithm;
    }

    public void setAlgorithm(String algorithm) {
        this.algorithm = algorithm;
    }

    public boolean isKeyRotationEnabled() {
        return keyRotationEnabled;
    }

    public void setKeyRotationEnabled(boolean keyRotationEnabled) {
        this.keyRotationEnabled = keyRotationEnabled;
    }

    public long getKeyRotationPeriodInDays() {
        return keyRotationPeriodInDays;
    }

    public void setKeyRotationPeriodInDays(long keyRotationPeriodInDays) {
        this.keyRotationPeriodInDays = keyRotationPeriodInDays;
    }

    public int getMinTokenLength() {
        return minTokenLength;
    }

    public void setMinTokenLength(int minTokenLength) {
        this.minTokenLength = minTokenLength;
    }
}