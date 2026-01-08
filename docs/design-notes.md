# Design notes – huffman-compressor
> Appunti di progettazione per un compressore testuale a strati (“huffman”) focalizzato sull’italiano e sulla struttura linguistica.

---

## 1. Obiettivi del progetto

### 1.1 Obiettivo principale

`huffman-compressor` **non** nasce per battere gzip, zstd, ecc.  
L’obiettivo è:
- sperimentare **come diversi livelli di struttura linguistica** influenzano la compressione,
- avere un laboratorio per:
  - prototipare idee,
  - misurare effetti di pre-processing diversi,
  - capire i compromessi tra:
    - semplicità,
    - dimensione degli header,
    - complessità linguistica.

In sintesi: è un progetto **didattico / di ricerca personale**, non un prodotto industriale.

### 1.2 Principi chiave

- **Layered design**: ogni “Step” aggiunge un livello di pre-processing, ma riusa lo stesso core di compressione (Huffman).
- **Lossless**: tutti i formati v1–v4 (e futuri) devono permettere di ricostruire il testo originale esattamente.
- **Sperimentale**: formati, layout e API possono cambiare. Non è garantita la compatibilità lunga nel tempo.
- **Bottom-up + top-down ibrido**:
  - conceptual design pensato dall’alto (lemmi, morfologia, linguistica),
  - implementazione incrementale dal basso (byte → V/C/O → sillabe → parole → lemmi).

---

## 2. Strati della “huffman linguistica”

L’idea di base: un testo ha molti livelli “strutturali”.  
`huffman-compressor` li esplora uno alla volta.

### 2.1 Strato 0 – Byte grezzi (Step1 / v1)

- Rappresentazione classica: sequenza di byte.
- Nessuna consapevolezza di lettere, parole, lingua.
- Compressione tradizionale: Huffman, LZ, ecc.

Nel progetto, questo è lo **Step 1 (v1)**:  
**Huffman sui byte** con un header ora **compattato** (si salvano solo i simboli con frequenza > 0).

È il baseline “onesto” contro cui confrontare gli altri Step.

---

### 2.2 Strato 1 – Lettere: vocali vs consonanti (Step2 / v2)

L’italiano (e le lingue alfabetiche in generale) hanno una struttura fonologica:

- le **vocali** sono poche ma frequenti (`a,e,i,o,u`),
- le **consonanti** sono più varie,
- vocali e consonanti alternano in pattern abbastanza regolari.

Lo **Step 2 (v2)** prova a sfruttare questo:

- separa il testo in:
  - una **maschera V/C/O**,
  - uno stream di **vocali**,
  - uno stream di **consonanti + altri simboli**,
- comprime i tre stream separatamente con Huffman.

Obiettivo concettuale:

- se la struttura V/C/O è molto regolare, la maschera può comprimersi bene;
- alfabeti ridotti (vocali) dovrebbero produrre codici più corti.

Esiti empirici (con i file di test attuali):

- su `small` (~1KB), `medium` (~4.6KB) e `large` (~600KB):
  - v2 è **sempre peggiore** di v1 in rapporto di compressione,
  - su file piccoli/medi addirittura *ingrassa* parecchio rispetto all’originale.

Motivo principale:

- tre header Huffman distinti (mask/vowels/cons) costano molto,
- il guadagno sui singoli stream non compensa l’overhead aggiuntivo.

Conclusione attuale: **Step2 è tenuto come esperimento didattico**, non come formato “competitivo”.

---

### 2.3 Strato 2 – Sillabe (pseudo-sillabe, Step3 / v3)

Le sillabe sono un’unità intermedia tra lettere e parole:

- riflettono struttura fonetica/articolatoria,
- in molte lingue (incluso l’italiano) hanno pattern frequenti (`-re`, `-zione`, `con-`, ecc.).

Step 3 (v3) introduce:

- una tokenizzazione in:
  - **sequenze di lettere** (parole),
  - **sequenze di non-lettere** (spazi, punteggiatura, ecc.);
- le sequenze di lettere vengono spezzate in **pseudo-sillabe** con una regola grezza:
  - taglio dopo ogni vocale;
- si costruisce un **vocabolario di token** (sillabe + blocchi non-lettera);
- si comprime la **sequenza di ID dei token** con Huffman, su un alfabeto di dimensione `VOCAB_SIZE`.

Evoluzione importante:

- in origine v3 aveva:
  - `VOCAB_SIZE` limitato a 256,
  - tabella frequenze fissa `FREQ[256]` sugli ID;
- ora v3 è stato generalizzato a **K simboli**:
  - `VOCAB_SIZE` è un `u32`,
  - le frequenze sono `FREQ_ID[VOCAB_SIZE]`,
  - Huffman lavora su ID `0..VOCAB_SIZE-1` senza limite artificiale 256.

Effetti pratici (sui test attuali):

- su `small` (~1KB): v3 ingrossa il file (header vocabolario + freq) → rapporto ~1.665;
- su `medium` (~4.6KB): v3 è quasi neutro rispetto all’originale (rapporto ~1.002);
- su `large` (~600KB): v3 **batte v1** (rapporto ~0.434 vs ~0.555 di v1).

Interpretazione:

- la struttura a sillabe + vocabolario ha senso **solo quando il testo è abbastanza lungo**
  da ripagare il costo del vocabolario e della tabella di frequenze.

---

### 2.4 Strato 3 – Parole intere (Step4 / v4)

Le **parole intere** sono un livello superiore:

- catturano unità lessicali,
- si ripetono spesso in un testo (frequenze di Zipf, ecc.),
- sono la base per passare poi a lemmi e morfologia.

Step 4 (v4) fa:

- tokenizzazione in:
  - sequenze di lettere ASCII → **parole**,
  - sequenze di non-lettere → **blocchi** separati;
- costruzione di un vocabolario di token (parole + blocchi);
- compressione della sequenza di ID dei token con Huffman, su alfabeto `0..VOCAB_SIZE-1` (come v3).

Anche v4 è stato portato al modello **K-simboli**:

- `VOCAB_SIZE` è `u32`,
- frequenze: `FREQ_ID[VOCAB_SIZE]`,
- Huffman sugli ID, senza limite 256.

Esiti empirici sui file di test:

- `small` (~1KB):
  - v4 ingrassa: rapporto ~1.729 (header troppo pesante);
- `medium` (~4.6KB):
  - v4 ancora peggiore dell’originale: rapporto ~1.389;
- `large` (~600KB):
  - v4 **batte nettamente v1**:
    - v1 (byte-level): rapporto ~0.555,
    - v4 (parole): rapporto ~0.236.

Quindi, su testi lunghi:

> **Parole intere + vocabolario + ID Huffman** diventano molto più efficienti
> del semplice Huffman sui byte.

Questo conferma sperimentalmente l’idea di partenza del progetto:
> sfruttare la struttura linguistica su testi lunghi può portare a compressione molto migliore.

---

### 2.5 Strato 4 – Lemmi e morfologia (idea Step5)

Strato più alto: **significato lessicale** + **forma morfologica**.

Obiettivo di Step 5 (non ancora implementato):

- trasformare le parole in:
  - **lemma** (forma base: *andare*, *mare*, *bello*),
  - **tag morfologico** (parte del discorso, tempo, persona, genere, numero, ecc.),
- separare:
  - il contenuto “di base” (sequenza di lemmi),
  - le informazioni “di superficie” (tag).

Schema ideale:

- tokenizzazione come v4 (parole / non-parole),
- lemmatizzazione delle parole → `(lemma, tag)` per ogni parola,
- vocabolari separati:
  - `lemma_vocab`,
  - `tag_vocab`,
  - `other_vocab` (blocchi non-lettera),
- compressione separata di:
  - `lemma_ids`,
  - `tag_ids`,
  - `other_ids`.

Note:

- per rimanere totalmente **lossless**, serve:
  - un generatore morfologico affidabile:
    - `generate(lemma, tag) -> surface_form`,
  - o un dizionario delle forme originali per “correggere” eventuali ambiguità.
- Step 5 è per ora un livello **concettuale**, documentato ma non codificato.

---

## 3. Filosofia di implementazione

### 3.1 Core Huffman riusabile

Il progetto si basa su un **core Huffman** unico:

- funzioni generiche:
  - costruzione tabella frequenze (lista di `u32`),
  - albero di Huffman,
  - tabella dei codici,
  - encode/decode di bitstream,
- usato da tutti gli Step (v1–v4, futuro v5),
- con varianti:
  - su byte (v1/v2),
  - su ID di token (v3/v4) tramite helper dedicati.

I vari Step differiscono solo per il **pre-processing** e per il formato dell’**header**.

### 3.2 Formati monolitici, poi ottimizzati

Impostazione attuale:

- gli header (soprattutto v2–v4) sono volutamente **ridondanti e verbosi**:
  - tabelle di frequenze complete per ogni stream,
  - vocabolari espliciti salvati in chiaro,
  - lunghezze salvate in `u64` anche dove basterebbe meno;
- questo aumenta l’overhead sui file piccoli, ma:
  - rende i formati più semplici da capire e debug,
  - fa da base per successivi esperimenti di **ottimizzazione header**.

L’idea è:
1. partire da formati “naïf ma chiari”,
2. misurare,
3. ottimizzare header/payload solo quando serve, tenendo sempre la vecchia versione come documentazione.

### 3.3 Trade-off: header vs guadagno

Il progetto mette in luce un concetto spesso invisibile nei compressori reali:

> un modello più intelligente non è gratis:  
> costa header, vocabolari, metadati.

Alcuni Step (es. v2, v3, v4):

- hanno pre-processing concettualmente sensato,
- ma nella pratica possono **peggiorare** la dimensione totale per file piccoli/medi, perché:
  - ogni livello porta vocabolari o tabelle aggiuntive,
  - i benefici nel bitstream non compensano (subito) il costo dell’header.

Con i dati attuali:

- v1 (byte) è il baseline robusto su tutte le taglie,
- v2 (V/C/O) perde sempre contro v1 (ed è tenuto come esperimento concettuale),
- v3 (sillabe) e v4 (parole) diventano interessanti **solo su testi lunghi**, dove:

  | File                | v1 (bytes) | v3 (sillabe) | v4 (parole) |
  |---------------------|-----------:|-------------:|------------:|
  | small (~1KB)        | 0.801      | 1.665        | 1.729       |
  | medium (~4.6KB)     | 0.628      | 1.002        | 1.389       |
  | large (~600KB)      | 0.555      | 0.434        | **0.236**   |

(valori ~indicativi basati su `tests/data/*`)

---

## 4. Roadmap concettuale (mini)

Riassunto della roadmap (da leggere insieme a `docs/roadmap.md`):

### 4.1 Fase 0 – Stabilizzare il prototipo Python

- Garantire test di roundtrip per v1–v4.
- Script di benchmark di base (come `bench_all.sh`).

### 4.2 Fase 1 – Ottimizzazione header e K-simboli

- Header v1 compresso (già fatto).
- Generalizzare v3/v4 a **K simboli** (già fatto a livello di formato + implementazione Python).
- In futuro: ridurre l’overhead delle tabelle di frequenze e dei vocabolari per v2–v4.

### 4.3 Fase 2 – Lemmatizzatore & Step5

- Integrare un lemmatizzatore italiano (quando/SE sarà opportuno).
- Definire e sperimentare un formato v5 per lemmi + tag.

### 4.4 Fase 3 – Porting in C

- Portare il **core Huffman** in C (v1),
- eventualmente anche tokenizzazione e formati a parole (v4).

---

## 5. Note finali

`huffman-compressor` è una **sandbox linguistico-algoritmica**:

- serve più a fare domande che a dare risposte definitive,
- mira a rendere espliciti i layer che spesso i compressori “seri” nascondono dentro modelli complessi.

Domande che il progetto vuole rendere esplorabili:

- Quanto conviene davvero usare:
  - lettere,
  - sillabe,
  - parole,
  - lemmi,
  come unità di compressione?
- Quanto costa portarsi dietro il “sapere linguistico” (vocabolari, tag, modelli)?
- Dove si trova il “punto dolce” tra:
  - **intelligenza del modello**,
  - **peso degli header**,
  - **semplicità di implementazione**?

Il progetto non pretende di rispondere in modo definitivo,  
ma vuole fornire un terreno di gioco dove è facile:

- cambiare una cosa alla volta,
- misurare,
- ragionare.

E, possibilmente, **divertirsi un po’ con la linguistica e la compressione**, che male non fa. 🍝🧠
