# Benchmarks – huffman-compressor

Questa pagina raccoglie i risultati **di riferimento** ottenuti con gli script di benchmark inclusi nel progetto.

I numeri servono solo come fotografia dello stato attuale (prototipo Python), non come “promessa” di performance stabili.

---

## 1. Setup

- Implementazione: `src/python/gcc_huffman.py`
- Script usati:
  - `tests/run_roundtrip.sh` – verifica roundtrip (lossless) per v1–v4
  - `scripts/bench_all.sh` – benchmark v1–v4 su tre file di esempio
- File di test:
  - `tests/data/small.txt`   (~1 KB) – testo breve
  - `tests/data/medium.txt`  (~4.6 KB) – testo descrittivo
  - `tests/data/large.txt`   (~628 KB) – testo lungo in italiano

Per ciascun file si riporta:

- dimensione originale,
- dimensione compressa,
- `ratio = size_compressed / size_original` (1.0 = nessuna compressione).

---

## 2. Risultati riassunti

### 2.1 Tabella sintetica (ratio)

| File                 | v1 (bytes) | v2 (V/C/O) | v3 (sillabe) | v4 (parole) |
|----------------------|-----------:|-----------:|-------------:|------------:|
| small (~1 KB)        | **0.801**  | 3.651      | 1.665        | 1.729       |
| medium (~4.6 KB)     | **0.628**  | 1.310      | 1.002        | 1.389       |
| large (~628 KB)      | 0.555      | 0.640      | 0.434        | **0.236**   |

Lettura rapida:

- su file piccoli/medi:
  - **v1** è l’unico vero “compressore”,
  - v2–v4 spesso **ingrassano** il file per via dell’overhead di header/vocabolari;
- su file grandi:
  - v4 (parole intere) diventa il chiaro vincitore,
  - anche v3 (sillabe) batte v1 in rapporto di compressione.

---

## 3. Dettaglio per file

### 3.1 `tests/data/small.txt` (1038 byte)

| Step                 | Size compresso (byte) | Ratio  |
|----------------------|----------------------:|-------:|
| v1 – bytes           | 831                   | 0.801  |
| v2 – V/C/O           | 3790                  | 3.651  |
| v3 – sillabe         | 1728                  | 1.665  |
| v4 – parole          | 1795                  | 1.729  |

Osservazioni:

- gli header (specie vocabolari + tabelle freq) dominano il costo,
- gli Step “intelligenti” (v2–v4) sono peggiori dell’originale,
- questo è atteso: il modello è più complesso del contenuto da comprimere.

---

### 3.2 `tests/data/medium.txt` (4615 byte)

| Step                 | Size compresso (byte) | Ratio  |
|----------------------|----------------------:|-------:|
| v1 – bytes           | 2900                  | 0.628  |
| v2 – V/C/O           | 6046                  | 1.310  |
| v3 – sillabe         | 4623                  | 1.002  |
| v4 – parole          | 6408                  | 1.389  |

Osservazioni:

- v1 continua ad essere la scelta “sana” per la compressione reale,
- v3 è quasi neutro (ratio ~1.0): il vocabolario inizia a ripagarsi,
- v4 e v2 sono ancora troppo pesanti in header per vincere sui byte grezzi.

---

### 3.3 `tests/data/large.txt` (628014 byte)

| Step                 | Size compresso (byte) | Ratio  |
|----------------------|----------------------:|-------:|
| v1 – bytes           | 348839                | 0.555  |
| v2 – V/C/O           | 401769                | 0.640  |
| v3 – sillabe         | 272731                | 0.434  |
| v4 – parole          | 148262                | 0.236  |

Osservazioni:

- v2 continua a perdere rispetto a v1 (overhead superiore al guadagno),
- v3 (sillabe) **migliora** rispetto al baseline byte-level: 0.434 vs 0.555,
- v4 (parole intere) è il grande vincitore: ~0.236, molto meglio di v1.

Questa è la prima evidenza sperimentale chiara che:

> per testi lunghi, il livello “parole + vocabolario + ID Huffman”
> può battere nettamente il semplice Huffman sui byte.

---

## 4. Come rigenerare i benchmark

Dalla root del progetto:

```bash
# Verifica che la compressione/decompressione sia lossless
tests/run_roundtrip.sh

# Esegui i benchmark v1–v4 su small/medium/large
scripts/bench_all.sh
```

Se i formati o l’implementazione cambiano, i numeri qui riportati possono diventare obsoleti.  
In quel caso, è consigliabile:

1. rigenerare i benchmark,
2. aggiornare questa pagina con i nuovi valori,
3. aggiungere, se utile, un riferimento al tag Git corrispondente (es. `v0.2.0`).

---

## 5. Uso di questi numeri

I valori di questa pagina servono a:

- confrontare gli Step tra loro (v1 vs v2 vs v3 vs v4),
- avere un punto fisso per notare regressioni o miglioramenti,
- ragionare sui compromessi tra:
  - overhead degli header,
  - complessità del modello linguistico,
  - lunghezza del testo.

Non vanno interpretati come “garanzia di performance” su testi generici,  
ma come **foto di laboratorio** dello stato del progetto in questa fase.
