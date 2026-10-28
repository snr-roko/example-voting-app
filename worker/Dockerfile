# --- build stage: compile the application ---
FROM --platform=${BUILDPLATFORM} mcr.microsoft.com/dotnet/sdk:10.0 AS build

ARG TARGETPLATFORM
ARG TARGETARCH
ARG BUILDPLATFORM

WORKDIR /source

# Copy project file and restore dependencies
COPY *.csproj .
RUN dotnet restore -a $TARGETARCH

# Copy all source code and build
COPY . .
RUN dotnet publish -c release -o /app -a $TARGETARCH --self-contained false --no-restore

# --- final stage: runtime ---
FROM mcr.microsoft.com/dotnet/runtime:10.0 AS final

WORKDIR /app

# Create a non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser -m -s /sbin/nologin appuser

# Copy published application from build stage
COPY --from=build /app .

# Expose port (worker internally doesn't listen on a port, but we expose for healthcheck)
EXPOSE 80

# Run as non-root user
USER appuser

# Entry point: run the .NET worker DLL
ENTRYPOINT ["dotnet", "Worker.dll"]



