#include "DHT.h"
#include "max6675.h"

// ----- DHT11 -----
#define DHTPIN A0
#define DHTTYPE DHT11
DHT dht(DHTPIN, DHTTYPE);

// ----- MAX6675 -----
const int thermoDO  = 4;   // SO/DO
const int thermoCS  = 5;   // CS
const int thermoCLK = 6;   // SCK
MAX6675 tc(thermoCLK, thermoCS, thermoDO);

float leerTC_filtrado(uint8_t n = 4) {
  // MAX6675 requiere ~220 ms entre conversiones
  float s = 0;
  for (uint8_t i = 0; i < n; i++) {
    s += tc.readCelsius();
    delay(250);
  }
  return s / n;
}

void setup() {
  Serial.begin(9600);
  dht.begin();
  delay(500);
}

void loop() {
  // Lecturas
  float h   = dht.readHumidity();
  float tdh = dht.readTemperature(); // °C
  float ttc = leerTC_filtrado(4);

  // Validación básica
  if (isnan(h) || isnan(tdh) || isnan(ttc)) {
    delay(5000); // esperar igual los 5 s aunque falle
    return;
  }

  // Salida CSV: ms,humedad,temp_dht,temp_tc
  Serial.print(millis()); Serial.print(",");
  Serial.print(h,   2);   Serial.print(",");
  Serial.print(tdh, 2);   Serial.print(",");
  Serial.println(ttc, 2);

  delay(5000); // cada 5 segundos un muestra de dato
}
