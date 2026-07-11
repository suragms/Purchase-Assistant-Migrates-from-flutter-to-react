FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/Domain/PurchaseAssistant.Domain.csproj src/Domain/
COPY src/Application/PurchaseAssistant.Application.csproj src/Application/
COPY src/Infrastructure/PurchaseAssistant.Infrastructure.csproj src/Infrastructure/
COPY src/Api/PurchaseAssistant.Api.csproj src/Api/
RUN dotnet restore src/Api/PurchaseAssistant.Api.csproj

COPY . .
RUN dotnet publish src/Api/PurchaseAssistant.Api.csproj -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
EXPOSE 8080
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:8080
ENTRYPOINT ["dotnet", "PurchaseAssistant.Api.dll"]
