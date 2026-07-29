# eChůvička (iOS, iPadOS, macOS)

Nativní aplikace chůvičky pro Apple zařízení. Přenáší obousměrný zvuk bez nutnosti internetového připojení prostřednictvím lokalního spojení (Wi-Fi Router) a Direct Peer-to-Peer (Wi-Fi Direct / Ad-hoc D2D).

## Hlavní funkce
- **Platformy:** Universal SwiftUI pro iPhone, iPad a Mac.
- **Konektivita:** Dynamické přepínání mezi Router (DRD) a Direct P2P (D2D) podle kvality signálu (latence a ztrátovosti paketů).
- **Zabezpečení:** Párování a šifrování relace pomocí 6místného PIN kódu (CryptoKit).
- **Audio:** Nízko-latentní přenos hlasu (AVAudioEngine + Opus/AAC), obousměrný Push-to-Talk pro rodiče.
- **Úspora baterie:** Podpora detekce zvuku (VOX), provoz se zhasnutou obrazovkou na pozadí (Background Audio/VoIP).
- **Alerting:** Nastavitelný alarm při ztrátě signálu nebo vybití baterie u dětské jednotky.

## Repozitář
- GitHub: [https://github.com/Hnzti/eChuvicka](https://github.com/Hnzti/eChuvicka)
