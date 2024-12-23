# Build stage
FROM eclipse-temurin:17-jdk-alpine AS build
LABEL stage=builder

# Set working directory
WORKDIR /workspace/app

# Install build dependencies and security updates
RUN apk update && apk upgrade && \
    apk add --no-cache curl=~8.4 maven=~3.9 git=~2.43 && \
    rm -rf /var/cache/apk/*

# Copy Maven wrapper files
COPY .mvn .mvn
COPY mvnw mvnw.cmd ./
RUN chmod +x mvnw

# Copy and verify pom.xml
COPY pom.xml .
RUN ./mvnw dependency:go-offline -B

# Copy source code
COPY src src/

# Security scan and build
RUN ./mvnw verify -B && \
    ./mvnw spring-boot:build-image -B -DskipTests && \
    ./mvnw dependency:tree

# Extract layers for better caching
RUN mkdir -p target/extracted && \
    java -Djarmode=layertools -jar target/auth-service.jar extract --destination target/extracted

# Runtime stage
FROM eclipse-temurin:17-jre-alpine
LABEL maintainer="Wildlife Safari Pokédex Team" \
      application="auth-service" \
      version="${project.version}" \
      security.protocol="oauth2-oidc"

# Install security updates and required packages
RUN apk update && apk upgrade && \
    apk add --no-cache curl=~8.4 tini=~0.19 && \
    rm -rf /var/cache/apk/*

# Create non-root user
RUN addgroup -S appgroup && \
    adduser -S -G appgroup appuser && \
    mkdir -p /app/logs /app/config /tmp && \
    chown -R appuser:appgroup /app /tmp

# Set working directory
WORKDIR /app

# Copy application layers from build stage
COPY --from=build --chown=appuser:appgroup /workspace/app/target/extracted/dependencies/ ./
COPY --from=build --chown=appuser:appgroup /workspace/app/target/extracted/spring-boot-loader/ ./
COPY --from=build --chown=appuser:appgroup /workspace/app/target/extracted/snapshot-dependencies/ ./
COPY --from=build --chown=appuser:appgroup /workspace/app/target/extracted/application/ ./

# Configure security
RUN chmod -R 550 /app && \
    chmod -R 770 /app/logs /app/config /tmp

# Set environment variables
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 \
    -XX:InitialRAMPercentage=50.0 \
    -XX:+UseG1GC \
    -XX:+HeapDumpOnOutOfMemoryError \
    -XX:HeapDumpPath=/app/logs \
    -Dfile.encoding=UTF-8 \
    -Djava.security.egd=file:/dev/urandom \
    -Dspring.security.oauth2.resourceserver.jwt.issuer-uri=${AUTH0_ISSUER_URI}" \
    SPRING_PROFILES_ACTIVE="prod" \
    OTEL_EXPORTER_OTLP_ENDPOINT="http://otel-collector:4317"

# Expose port
EXPOSE 8081

# Set volumes
VOLUME ["/app/logs", "/app/config", "/tmp"]

# Configure health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=40s \
    CMD curl -f http://localhost:8081/actuator/health || exit 1

# Set user
USER appuser

# Use tini as init
ENTRYPOINT ["/sbin/tini", "--"]

# Set the application startup command
CMD ["java", "org.springframework.boot.loader.JarLauncher"]

# Resource limits
LABEL org.opencontainers.image.resources.memory.limit="1Gi" \
      org.opencontainers.image.resources.memory.reservation="512Mi" \
      org.opencontainers.image.resources.cpu.limit="1.0" \
      org.opencontainers.image.resources.cpu.reservation="0.5"

# Security configurations
LABEL org.opencontainers.image.security.readonly-rootfs="true" \
      org.opencontainers.image.security.capabilities.drop="ALL" \
      org.opencontainers.image.security.capabilities.add="NET_BIND_SERVICE" \
      org.opencontainers.image.security.no-new-privileges="true"