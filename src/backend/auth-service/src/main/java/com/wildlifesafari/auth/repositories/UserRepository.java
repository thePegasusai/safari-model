package com.wildlifesafari.auth.repositories;

import com.wildlifesafari.auth.models.User;
import com.wildlifesafari.auth.models.User.UserRole;
import org.springframework.data.jpa.repository.JpaRepository; // spring-boot-starter-data-jpa:2.7.0
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import java.time.LocalDateTime; // java.time:11
import java.util.List; // java.util:11
import java.util.Optional; // java.util:11
import java.util.UUID; // java.util:11

/**
 * Repository interface for managing user data persistence with enhanced security features
 * and monitoring capabilities in the Wildlife Safari Pokédex application.
 * Implements comprehensive querying for user management, role-based access control,
 * and security monitoring.
 */
@Repository
public interface UserRepository extends JpaRepository<User, UUID> {

    /**
     * Finds a user by their email address with case-insensitive matching.
     * Used for authentication and user lookup operations.
     *
     * @param email The email address to search for
     * @return Optional containing the user if found
     */
    @Query("SELECT u FROM User u WHERE LOWER(u.email) = LOWER(:email)")
    Optional<User> findByEmail(@Param("email") String email);

    /**
     * Finds an enabled user by their email address for active user validation.
     * Used during authentication to ensure only active accounts can log in.
     *
     * @param email The email address to search for
     * @param enabled The enabled status to match
     * @return Optional containing the enabled user if found
     */
    @Query("SELECT u FROM User u WHERE LOWER(u.email) = LOWER(:email) AND u.enabled = :enabled")
    Optional<User> findByEmailAndEnabled(@Param("email") String email, @Param("enabled") boolean enabled);

    /**
     * Checks if a user exists with the given email address.
     * Used for duplicate email prevention during registration.
     *
     * @param email The email address to check
     * @return true if a user exists with the email
     */
    @Query("SELECT COUNT(u) > 0 FROM User u WHERE LOWER(u.email) = LOWER(:email)")
    boolean existsByEmail(@Param("email") String email);

    /**
     * Finds all users with a specific role for role-based access control.
     * Used for administrative operations and user management.
     *
     * @param role The role to search for
     * @return List of users with the specified role
     */
    @Query("SELECT u FROM User u WHERE u.role = :role ORDER BY u.createdAt DESC")
    List<User> findByRole(@Param("role") UserRole role);

    /**
     * Finds users who haven't logged in since a specific date.
     * Used for security monitoring and inactive account detection.
     *
     * @param date The date threshold for last login
     * @return List of users who haven't logged in since the specified date
     */
    @Query("SELECT u FROM User u WHERE u.lastLoginAt < :date OR u.lastLoginAt IS NULL")
    List<User> findByLastLoginAtBefore(@Param("date") LocalDateTime date);

    /**
     * Finds users by account status for monitoring and management.
     *
     * @param status The account status to search for
     * @return List of users with the specified status
     */
    @Query("SELECT u FROM User u WHERE u.status = :status ORDER BY u.modifiedAt DESC")
    List<User> findByStatus(@Param("status") User.AccountStatus status);

    /**
     * Finds users created within a specific date range for audit purposes.
     *
     * @param startDate The start of the date range
     * @param endDate The end of the date range
     * @return List of users created within the date range
     */
    @Query("SELECT u FROM User u WHERE u.createdAt BETWEEN :startDate AND :endDate ORDER BY u.createdAt DESC")
    List<User> findByCreatedAtBetween(
        @Param("startDate") LocalDateTime startDate,
        @Param("endDate") LocalDateTime endDate
    );

    /**
     * Counts the number of users by role for analytics and reporting.
     *
     * @param role The role to count
     * @return The number of users with the specified role
     */
    @Query("SELECT COUNT(u) FROM User u WHERE u.role = :role")
    long countByRole(@Param("role") UserRole role);
}