FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Directory.Build.props ./
COPY backend/src/Bma.Api/Bma.Api.csproj backend/src/Bma.Api/
RUN dotnet restore backend/src/Bma.Api/Bma.Api.csproj
COPY backend/src/Bma.Api/ backend/src/Bma.Api/
RUN dotnet publish backend/src/Bma.Api/Bma.Api.csproj -c Release -o /app/publish --no-restore /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
ENV ASPNETCORE_URLS=http://+:8080 \
    ASPNETCORE_ENVIRONMENT=Production \
    DOTNET_EnableDiagnostics=0
COPY --from=build /app/publish .
RUN mkdir -p /home/app/.aspnet/DataProtection-Keys \
    && chown -R app:app /home/app/.aspnet
USER app
EXPOSE 8080
ENTRYPOINT ["dotnet", "Bma.Api.dll"]
