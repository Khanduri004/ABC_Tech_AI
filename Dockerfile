# Stage 1: build the WAR with Maven and Java 17.
FROM maven:3.9.9-eclipse-temurin-17@sha256:82e47241881f23ad774f5db8829efca15758e8fdb5b1d64ea9f8d6420a85068e AS builder

WORKDIR /workspace

# Copy the POM first so dependency resolution can be cached separately.
COPY app/pom.xml app/pom.xml

# Copy application sources after the POM to preserve Docker layer caching.
COPY app/src app/src

RUN mvn --batch-mode --file app/pom.xml clean package -DskipTests \
    && rm -rf /root/.m2/repository

# Stage 2: run only the packaged WAR in Tomcat.
FROM tomcat:10.1-jre17-temurin@sha256:ce7019dcf6296fe26b95fbdf1c308c6032835f5e536c90f90fcdd0ac6c184633

ENV CATALINA_HOME=/usr/local/tomcat

# Remove sample applications, create a locked-down runtime user, and grant
# write access only to directories Tomcat uses for runtime state.
RUN rm -rf "${CATALINA_HOME}/webapps/"* \
    && groupadd --system appgroup \
    && useradd --system --gid appgroup --home-dir "${CATALINA_HOME}" --shell /usr/sbin/nologin appuser \
    && chown -R appuser:appgroup \
        "${CATALINA_HOME}/logs" \
        "${CATALINA_HOME}/temp" \
        "${CATALINA_HOME}/webapps" \
        "${CATALINA_HOME}/work"

COPY --from=builder --chown=appuser:appgroup \
    /workspace/app/target/ROOT.war \
    ${CATALINA_HOME}/webapps/ROOT.war

EXPOSE 8080

USER appuser

CMD ["catalina.sh", "run"]
