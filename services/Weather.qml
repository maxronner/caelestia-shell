pragma Singleton

import qs.config
import qs.utils
import Caelestia
import Quickshell
import QtQuick

Singleton {
    id: root

    property string city
    property string loc
    property var cc
    property list<var> forecast
    property list<var> hourlyForecast

    readonly property string icon: cc ? Icons.getWeatherIcon(cc.weatherCode) : "cloud_alert"
    readonly property string description: cc?.weatherDesc ?? qsTr("No weather")
    readonly property string temp: Config.services.useFahrenheit ? `${cc?.tempF ?? 0}°F` : `${cc?.tempC ?? 0}°C`
    readonly property string feelsLike: Config.services.useFahrenheit ? `${cc?.feelsLikeF ?? 0}°F` : `${cc?.feelsLikeC ?? 0}°C`
    readonly property int humidity: cc?.humidity ?? 0
    readonly property real windSpeed: cc?.windSpeed ?? 0
    readonly property string sunrise: cc ? Qt.formatDateTime(new Date(cc.sunrise), Config.services.useTwelveHourClock ? "h:mm A" : "h:mm") : "--:--"
    readonly property string sunset: cc ? Qt.formatDateTime(new Date(cc.sunset), Config.services.useTwelveHourClock ? "h:mm A" : "h:mm") : "--:--"

    readonly property var cachedCities: new Map()

    // Validates a coordinate string is a numeric lat/lon pair within valid ranges.
    // Rejects any non-numeric content that could pollute API URLs.
    function isValidCoords(coords: string): bool {
        if (!coords || coords.indexOf(",") === -1)
            return false;
        const parts = coords.split(",");
        if (parts.length !== 2)
            return false;
        const lat = parseFloat(parts[0]);
        const lon = parseFloat(parts[1]);
        return !isNaN(lat) && !isNaN(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
    }

    function reload(): void {
        const configLocation = Config.services.weatherLocation;

        if (configLocation) {
            if (isValidCoords(configLocation)) {
                loc = configLocation;
                fetchCityFromCoords(configLocation);
            } else {
                fetchCoordsFromCity(configLocation);
            }
        } else if (!loc || timer.elapsed() > 900) {
            // IP geolocation requires opt-in via Config.services.weatherAutoLocate
            // because it sends the user's IP address to a third-party service (ipinfo.io).
            if (!Config.services.weatherAutoLocate) {
                return;
            }
            Requests.get("https://ipinfo.io/json", text => {
                try {
                    const response = JSON.parse(text);
                    if (response.loc && isValidCoords(response.loc)) {
                        loc = response.loc;
                        city = response.city ?? "";
                        timer.restart();
                    }
                } catch (e) {
                    console.warn("Weather: failed to parse ipinfo.io response:", e);
                }
            });
        }
    }

    function fetchCityFromCoords(coords: string): void {
        if (cachedCities.has(coords)) {
            city = cachedCities.get(coords);
            return;
        }

        // Validate coords before interpolating into URL
        if (!isValidCoords(coords)) {
            console.warn("Weather: fetchCityFromCoords rejected invalid coords:", coords);
            return;
        }

        const parts = coords.split(",");
        const lat = encodeURIComponent(parts[0]);
        const lon = encodeURIComponent(parts[1]);
        const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=geocodejson`;
        Requests.get(url, text => {
            try {
                const geo = JSON.parse(text).features?.[0]?.properties.geocoding;
                if (geo) {
                    const geoCity = geo.type === "city" ? geo.name : geo.city;
                    city = geoCity;
                    cachedCities.set(coords, geoCity);
                } else {
                    city = "Unknown City";
                }
            } catch (e) {
                console.warn("Weather: failed to parse reverse geocode response:", e);
            }
        });
    }

    function fetchCoordsFromCity(cityName: string): void {
        const url = `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(cityName)}&count=1&language=en&format=json`;

        Requests.get(url, text => {
            try {
                const json = JSON.parse(text);
                if (json.results && json.results.length > 0) {
                    const result = json.results[0];
                    const newLat = parseFloat(result.latitude);
                    const newLon = parseFloat(result.longitude);
                    if (!isNaN(newLat) && !isNaN(newLon)) {
                        loc = newLat + "," + newLon;
                        city = result.name;
                    }
                } else {
                    loc = "";
                    reload();
                }
            } catch (e) {
                console.warn("Weather: failed to parse geocoding response:", e);
            }
        });
    }

    function fetchWeatherData(): void {
        const url = getWeatherUrl();
        if (url === "")
            return;

        Requests.get(url, text => {
            try {
            const json = JSON.parse(text);
            if (!json.current || !json.daily)
                return;

            cc = {
                weatherCode: json.current.weather_code,
                weatherDesc: getWeatherCondition(json.current.weather_code),
                tempC: Math.round(json.current.temperature_2m),
                tempF: Math.round(toFahrenheit(json.current.temperature_2m)),
                feelsLikeC: Math.round(json.current.apparent_temperature),
                feelsLikeF: Math.round(toFahrenheit(json.current.apparent_temperature)),
                humidity: json.current.relative_humidity_2m,
                windSpeed: json.current.wind_speed_10m,
                isDay: json.current.is_day,
                sunrise: json.daily.sunrise[0],
                sunset: json.daily.sunset[0]
            };

            const forecastList = [];
            for (let i = 0; i < json.daily.time.length; i++)
                forecastList.push({
                    date: json.daily.time[i],
                    maxTempC: Math.round(json.daily.temperature_2m_max[i]),
                    maxTempF: Math.round(toFahrenheit(json.daily.temperature_2m_max[i])),
                    minTempC: Math.round(json.daily.temperature_2m_min[i]),
                    minTempF: Math.round(toFahrenheit(json.daily.temperature_2m_min[i])),
                    weatherCode: json.daily.weather_code[i],
                    icon: Icons.getWeatherIcon(json.daily.weather_code[i])
                });
            forecast = forecastList;

            const hourlyList = [];
            const now = new Date();
            for (let i = 0; i < json.hourly.time.length; i++) {
                const time = new Date(json.hourly.time[i]);
                if (time < now)
                    continue;

                hourlyList.push({
                    timestamp: json.hourly.time[i],
                    hour: time.getHours(),
                    tempC: Math.round(json.hourly.temperature_2m[i]),
                    tempF: Math.round(toFahrenheit(json.hourly.temperature_2m[i])),
                    weatherCode: json.hourly.weather_code[i],
                    icon: Icons.getWeatherIcon(json.hourly.weather_code[i])
                });
            }
            hourlyForecast = hourlyList;
            } catch (e) {
                console.warn("Weather: failed to parse weather data response:", e);
            }
        });
    }

    function toFahrenheit(celcius: real): real {
        return celcius * 9 / 5 + 32;
    }

    function getWeatherUrl(): string {
        if (!isValidCoords(loc))
            return "";

        const parts = loc.split(",");
        const lat = encodeURIComponent(parts[0]);
        const lon = encodeURIComponent(parts[1]);
        const baseUrl = "https://api.open-meteo.com/v1/forecast";
        const params = ["latitude=" + lat, "longitude=" + lon, "hourly=weather_code,temperature_2m", "daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset", "current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m", "timezone=auto", "forecast_days=7"];

        return baseUrl + "?" + params.join("&");
    }

    function getWeatherCondition(code: string): string {
        const conditions = {
            "0": "Clear",
            "1": "Clear",
            "2": "Partly cloudy",
            "3": "Overcast",
            "45": "Fog",
            "48": "Fog",
            "51": "Drizzle",
            "53": "Drizzle",
            "55": "Drizzle",
            "56": "Freezing drizzle",
            "57": "Freezing drizzle",
            "61": "Light rain",
            "63": "Rain",
            "65": "Heavy rain",
            "66": "Light rain",
            "67": "Heavy rain",
            "71": "Light snow",
            "73": "Snow",
            "75": "Heavy snow",
            "77": "Snow",
            "80": "Light rain",
            "81": "Rain",
            "82": "Heavy rain",
            "85": "Light snow showers",
            "86": "Heavy snow showers",
            "95": "Thunderstorm",
            "96": "Thunderstorm with hail",
            "99": "Thunderstorm with hail"
        };
        return conditions[code] || "Unknown";
    }

    onLocChanged: fetchWeatherData()

    // Refresh current location hourly
    Timer {
        interval: 3600000 // 1 hour
        running: true
        repeat: true
        onTriggered: fetchWeatherData()
    }

    ElapsedTimer {
        id: timer
    }
}
