package com.wildlifesafari.auth.models;

import javax.persistence.Entity; // javax.persistence:javax.persistence-api:2.2
import javax.persistence.Table;
import javax.persistence.Id;
import javax.persistence.GeneratedValue;
import javax.persistence.Column;
import javax.persistence.Enumerated;
import javax.persistence.EnumType;
import javax.persistence.EntityListeners;
import javax.persistence.PrePersist;
import javax.persistence.Version;
import java.util.UUID; // java.util:11
import java.time.LocalDateTime; // java.time:11
import java.util.regex.Pattern;

/**
 * Entity class representing a user in the Wildlife Safari Pokédex application.
 * Implements comprehensive security features including role-based access control
 * and audit logging capabilities.
 */
@Entity
@Table(name = "users")
@EntityListeners(AuditingEntityListener.class)
public class User {

    // Email validation pattern
    private static final Pattern EMAIL_PATTERN = 
        Pattern.compile("^[A-Za-z0-9+_.-]+@(.+)$");

    /**
     * Enumeration of possible user roles with increasing privilege levels
     */
    public enum UserRole {
        ANONYMOUS,
        BASIC_USER,
        RESEARCHER,
        MODERATOR,
        ADMINISTRATOR
    }

    /**
     * Enumeration of possible user account states
     */
    public enum AccountStatus {
        PENDING,
        ACTIVE,
        SUSPENDED,
        LOCKED,
        DELETED
    }

    @Id
    @GeneratedValue
    @Column(name = "id", updatable = false, nullable = false)
    private UUID id;

    @Column(name = "email", unique = true, nullable = false, length = 255)
    private String email;

    @Column(name = "password", nullable = false, columnDefinition = "CHAR(60)")
    private String password;

    @Column(name = "name", length = 100)
    private String name;

    @Enumerated(EnumType.STRING)
    @Column(name = "role", nullable = false)
    private UserRole role;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private AccountStatus status;

    @Column(name = "enabled", nullable = false)
    private boolean enabled;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "created_by", nullable = false, updatable = false)
    private String createdBy;

    @Column(name = "modified_at")
    private LocalDateTime modifiedAt;

    @Column(name = "modified_by")
    private String modifiedBy;

    @Column(name = "last_login_at")
    private LocalDateTime lastLoginAt;

    @Version
    @Column(name = "version")
    private Long version;

    /**
     * Default constructor with initialization of required fields
     */
    public User() {
        this.enabled = false;
        this.status = AccountStatus.PENDING;
        this.role = UserRole.BASIC_USER;
        this.createdAt = LocalDateTime.now();
        this.version = 0L;
    }

    /**
     * Lifecycle callback executed before entity persistence
     */
    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
        if (this.createdBy == null) {
            this.createdBy = "SYSTEM";
        }
    }

    /**
     * Gets the user's unique identifier
     * @return User's UUID
     */
    public UUID getId() {
        return id;
    }

    /**
     * Gets the user's email address
     * @return User's email address
     */
    public String getEmail() {
        return email;
    }

    /**
     * Sets and validates the user's email address
     * @param email The email address to set
     * @throws IllegalArgumentException if email format is invalid
     */
    public void setEmail(String email) {
        if (email == null || !EMAIL_PATTERN.matcher(email).matches()) {
            throw new IllegalArgumentException("Invalid email format");
        }
        this.email = email.toLowerCase();
    }

    /**
     * Gets the user's current role
     * @return Current UserRole
     */
    public UserRole getRole() {
        return role;
    }

    /**
     * Sets the user's role
     * @param role New UserRole to assign
     */
    public void setRole(UserRole role) {
        this.role = role;
    }

    /**
     * Gets the user's account status
     * @return Current AccountStatus
     */
    public AccountStatus getStatus() {
        return status;
    }

    /**
     * Sets the user's account status
     * @param status New AccountStatus to assign
     */
    public void setStatus(AccountStatus status) {
        this.status = status;
    }

    /**
     * Updates the last login timestamp and audit fields
     * @param modifiedBy Username of the modifier
     */
    public void updateLastLogin(String modifiedBy) {
        this.lastLoginAt = LocalDateTime.now();
        this.modifiedAt = LocalDateTime.now();
        this.modifiedBy = modifiedBy;
    }

    /**
     * Checks if user has specific role or higher
     * @param requiredRole The minimum role required
     * @return true if user has required role or higher
     */
    public boolean hasRole(UserRole requiredRole) {
        return this.role.ordinal() >= requiredRole.ordinal();
    }

    /**
     * Sets the password hash
     * @param passwordHash BCrypt hashed password
     */
    public void setPassword(String passwordHash) {
        this.password = passwordHash;
    }

    /**
     * Gets the password hash
     * @return BCrypt hashed password
     */
    protected String getPassword() {
        return password;
    }

    /**
     * Gets the user's enabled status
     * @return true if account is enabled
     */
    public boolean isEnabled() {
        return enabled;
    }

    /**
     * Sets the user's enabled status
     * @param enabled New enabled status
     */
    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    /**
     * Gets the entity version for optimistic locking
     * @return Current version number
     */
    public Long getVersion() {
        return version;
    }
}