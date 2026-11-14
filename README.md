# Bacheca Lavoro — backend

Backend REST della bacheca di annunci di lavoro: le aziende si registrano, pubblicano
annunci e consultano le candidature; i candidati (senza account) inviano i propri dati e
il curriculum in PDF. Scritto in **Dart** con [shelf](https://pub.dev/packages/shelf) e
[shelf_router](https://pub.dev/packages/shelf_router), senza servizi esterni: i dati
stanno su file JSON e i PDF in una cartella sul disco.

Progetto client: **bacheca-lavoro-app** (Flutter).

---

## Requisiti

- Dart SDK 3.x (testato con Dart 3.13.5 / Flutter 3.47)
- Nessun database, nessun servizio cloud

## Avvio

```bash
cd server
dart pub get
dart run bin/server.dart
```

Il server ascolta su `0.0.0.0:8080` e stampa all'avvio gli indirizzi da usare:

```
Bacheca lavoro - backend in ascolto sulla porta 8080
Dati persistenti in: /…/server/data
Simulatore iOS / macOS / browser: http://127.0.0.1:8080
Emulatore Android: http://10.0.2.2:8080
Telefono reale: http://192.168.x.x:8080
```

Variabili d'ambiente facoltative:

| Variabile  | Default | Significato                          |
| ---------- | ------- | ------------------------------------ |
| `PORT`     | `8080`  | porta di ascolto                     |
| `DATA_DIR` | `data`  | cartella di dati e curriculum        |

Per ripartire da zero: fermare il server e cancellare `data/`.

## Persistenza

Tutto ciò che serve alla demo resta su disco dentro `data/`:

```
data/
├── companies.json     account delle aziende (password con salt + SHA-256)
├── jobs.json          annunci pubblicati
├── applications.json  candidature con riferimento al PDF
└── uploads/           curriculum, un file per candidatura (nome casuale)
```

Le scritture sono atomiche (file temporaneo + rename) e serializzate da una coda, così
due richieste ravvicinate non corrompono i JSON. I dati sopravvivono al riavvio del
server; i **token di sessione** invece stanno in memoria: dopo un riavvio il client riceve
`401` e torna all'area pubblica (comportamento voluto, è la scadenza della sessione).

## API

Tutte le risposte sono JSON; gli errori hanno la forma `{"error": "messaggio"}`.
Le rotte marcate *token* richiedono `Authorization: Bearer <token>`.

### Autenticazione azienda

| Metodo | Rotta                | Body / Note                                    | Esito |
| ------ | -------------------- | ---------------------------------------------- | ----- |
| POST   | `/api/auth/register` | `{name, email, password}`                      | 201 `{token, company}` |
| POST   | `/api/auth/login`    | `{email, password}`                            | 200 `{token, company}` |
| POST   | `/api/auth/logout`   | *token* — revoca il token                      | 204 |
| GET    | `/api/auth/me`       | *token* — usata per ripristinare la sessione   | 200 `company` |

Regole: nome 2–80 caratteri, email valida e univoca (409 se già registrata), password
8–72 caratteri con almeno una lettera e un numero. La password non viene mai salvata in
chiaro.

### Annunci

| Metodo | Rotta                  | Note                                                    | Esito |
| ------ | ---------------------- | ------------------------------------------------------- | ----- |
| GET    | `/api/jobs?q=testo`    | bacheca pubblica, ricerca su titolo/azienda/sede/contratto | 200 `[job]` |
| GET    | `/api/jobs/{id}`       | dettaglio pubblico                                       | 200 `job` |
| GET    | `/api/jobs/mine`       | *token* — propri annunci con `applicationsCount`         | 200 `[job]` |
| POST   | `/api/jobs`            | *token* — `{title, description, location, contract, salary}` | 201 `job` |

`contract` accetta: `Tempo indeterminato`, `Tempo determinato`, `Apprendistato`,
`Stage`, `Part-time`, `Freelance`. `salary` è facoltativo.

### Candidature

| Metodo | Rotta                              | Note                                              | Esito |
| ------ | ---------------------------------- | ------------------------------------------------- | ----- |
| POST   | `/api/jobs/{id}/applications`      | **pubblico**, `multipart/form-data`              | 201 `application` |
| GET    | `/api/jobs/{id}/applications`      | *token*, solo proprietario                        | 200 `{job, applications}` |
| GET    | `/api/applications/{id}`           | *token*, solo proprietario                        | 200 `application` |
| GET    | `/api/applications/{id}/cv?token=` | *token*, solo proprietario — PDF inline           | 200 `application/pdf` |

Campi del multipart: `firstName`, `lastName`, `email`, `message` (facoltativa), `cv`
(file). Il curriculum deve essere un **PDF** (verificato sull'intestazione `%PDF-`) di
massimo **5 MB**; viene salvato con un nome casuale e servito con il nome originale.

Il download del curriculum accetta il token anche come parametro `?token=`: serve perché
il client apre il PDF nel visualizzatore del sistema, fuori dall'app, dove non può
aggiungere header HTTP.

### Diagnostica

`GET /api/health` → `{"status":"ok","jobs":N,"applications":M}`

Codici di errore usati: `400` richiesta malformata, `401` autenticazione mancante o token
revocato, `403` risorsa di un'altra azienda, `404` non trovato, `409` email già
registrata, `413` file troppo grande, `422` dati non validi, `500` errore interno.

## Test

Con il server avviato, lo smoke test copre gli scenari S1–S3 (registrazione, login,
pubblicazione, bacheca, candidatura con PDF reale, consultazione, download del curriculum,
permessi tra aziende, logout):

```bash
./tool/smoke_test.sh                 # default http://127.0.0.1:8080
./tool/smoke_test.sh http://x:8080   # server su un'altra porta
```

Richiede `curl`, `jq` e `cupsfilter` (presente su macOS; su Linux si può sostituire la
riga che genera il PDF con un file PDF qualsiasi). Ultima esecuzione: **28 controlli
superati, 0 falliti**.

## Struttura

```
bin/server.dart                 avvio: DAO, middleware, router, stampa degli indirizzi
lib/controllers/                auth, job, application (rotte e logica applicativa)
lib/dao/                        json_store.dart + DAO per aziende, annunci, candidature
lib/models/                     Company, Job, Application, CvFile
lib/middleware/                 errorMiddleware (contratto errori), authMiddleware, CORS
lib/services/                   password (salt+SHA-256), token, CvStorage
lib/utils/                      validatori, parser multipart, formattazione date
tool/smoke_test.sh              test end-to-end da riga di comando
```

## Scelte tecniche e limiti noti

- **Niente servizi esterni**: persistenza su JSON + filesystem, come richiesto dal compito.
- **Password**: salt casuale di 16 byte e SHA-256, confronto a tempo costante. Per un
  progetto reale servirebbe un algoritmo lento (bcrypt/argon2) e HTTPS.
- **Token opachi in memoria**: semplici e senza dipendenze; un riavvio del server
  invalida le sessioni.
- **Multipart scritto a mano** con `package:mime`, con limite di dimensione: nessuna
  dipendenza da framework web completi.
- **CORS aperto**: solo per poter provare il client in Flutter web; in produzione va
  ristretto.
- **Nessuna paginazione**: la bacheca restituisce tutti gli annunci. Su volumi grandi
  servirebbe `limit`/`offset`.
- **Nessun deploy**: il server è pensato per girare sul computer locale durante la demo.
