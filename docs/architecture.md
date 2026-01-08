# Architecture – huffman-compressor
> Verso un framework di compressione testuale con layer semantici e codec pluggabili.

Questo documento descrive **come vogliamo ragionare** sull’architettura di `huffman-compressor` andando oltre l’attuale “monolite Huffman v1–v4`.

L’obiettivo non è solo comprimere testo italiano, ma costruire un **laboratorio estendibile** dove:

- il core di compressione è astratto (Huffman è solo il codec di default);
- la struttura del file (parole, lemmi, HTML `<body>`, “Lessons Learned”, ecc.) è gestita da **layer semantici** pluggabili;
- chiunque può implementare il proprio layer/codec senza toccare il core.

---

## 1. Tre attori: Layer, Codec, Engine

Concettualmente il sistema ha tre ruoli distinti:

1. **SemanticLayer** — decide “come vedere” il file:
   - testuale, binario, HTML, log, ecc.;
   - quali unità semantiche usare (byte, parole, lemmi, intestazioni, ecc.).

2. **Codec** — decide “come comprimere” la sequenza di simboli prodotta dal layer:
   - Huffman (default),
   - in futuro: LZ, arithmetic coding, codec personalizzati (“Pippo”, “Topolino”…).

3. **Engine/Container** — orchestra il tutto:
   - chiama `layer.encode` → `codec.compress`,
   - impacchetta il risultato in un formato binario con header (layer_id, codec_id, payload),
   - fa l’inverso in decompressione.

### 1.1 Interfaccia concettuale: SemanticLayer

Uno **strato semantico** decide come trasformare i byte originali in una rappresentazione “adatta” alla compressione, e come invertire il processo.

In pseudo-Python:

```python
class SemanticLayer:
    id = "nome-layer-univoco"  # es: "bytes_v1", "words_it_v1", "html_body_v1"

    def encode(self, data: bytes):
        """
        Input:
            data: bytes originali del file

        Output:
            symbols:    sequenza di simboli astratti da passare al Codec
                        (es. byte, ID di token, tuple, ecc.)
            layer_meta: metadati necessari per tornare ai bytes originali
                        (vocabolari, mappe, indici, ecc.)
        """
        ...

    def decode(self, symbols, layer_meta) -> bytes:
        """
        Deve ricostruire esattamente i bytes originali.
        """
        ...
```

Esempi di cosa può fare un layer:

- Tokenizzazione in parole (layer di parole italiane).
- Pseudo-sillabazione e blocchi non-lettera (layer v3 attuale).
- Estrazione di intestazioni “Lessons Learned” come entità speciali.
- HTML: scartare l’`<head>` e comprimere solo il `<body>` come contenuto principale.

L’unico vincolo è: `decode(encode(data))` deve restituire **gli stessi bytes**, altrimenti il layer non è valido come layer **lossless**.

### 1.2 Interfaccia concettuale: Codec

Il **codec** è il “cuoco” di compressione. Prende una sequenza di simboli e la schiaccia in un blob di bytes.

In pseudo-Python:

```python
class Codec:
    id = "huffman"  # oppure "pippo", "lz77", ecc.

    def compress(self, symbols, side_info=None) -> bytes:
        """
        symbols:   sequenza di simboli astratti (numeri, byte, ecc.)
        side_info: opzionale, se il layer vuole passare info extra
                   da salvare nel blob (può anche essere ignorato)

        Ritorna:
            blob di bytes compressi (formato interno del codec).
        """
        ...

    def decompress(self, blob: bytes):
        """
        Inverso di compress.
        Ritorna:
            symbols, side_info
        """
        ...
```

Nel progetto attuale:

- il “core Huffman” è una possibile implementazione di `Codec`:
  - `symbols` = byte (v1) o ID interi (v3/v4),
  - `side_info` = tabella di frequenze, dimensioni, ecc.,
  - `blob` = header Huffman + bitstream.

In futuro, altri codec possono convivere (LZ, misti, ecc.) senza cambiare i layer.

### 1.3 Engine / Container

L’**Engine** è l’orchestratore che combina un layer e un codec e scrive un contenitore binario unico.

Concetto:

```python
def compress_file(input_bytes: bytes,
                  layer: SemanticLayer,
                  codec: Codec) -> bytes:
    symbols, layer_meta = layer.encode(input_bytes)
    blob = codec.compress(symbols, side_info=layer_meta)
    return container_pack(
        layer_id=layer.id,
        codec_id=codec.id,
        payload=blob
    )

def decompress_file(container_bytes: bytes) -> bytes:
    layer_id, codec_id, blob = container_unpack(container_bytes)

    layer = registry_layers[layer_id]
    codec = registry_codecs[codec_id]

    symbols, layer_meta = codec.decompress(blob)
    data = layer.decode(symbols, layer_meta)
    return data
```

Il formato del contenitore potrebbe essere, concettualmente:

```text
MAGIC    = "GCC"
LAYER_ID = stringa fissa (es. "words_it_v1")
CODEC_ID = stringa fissa (es. "huffman")
PAYLOAD  = bytes prodotti da Codec.compress(...)
```

In pratica, useremo codifiche binarie più compatte (ID numerici, lunghezze, ecc.), ma l’idea è questa.

---

## 2. Rappresentazioni semantiche: livelli di “zoom”

È utile pensare ai layer come a **diversi livelli di zoom** sul testo:

- **Livello atomico (Layer1)** – singoli byte/char/lettere:
  - es. “ogni byte è un simbolo”, oppure “classifico ogni char come V/C/O”.

- **Livello molecolare (Layer2)** – parole, sillabe, lemmi, tag:
  - es. tokenizzazione in parole italiane (v4),
  - pseudo-sillabe + blocchi non-lettera (v3),
  - lemmi + tag morfologici (v5 futuro).

- **Livello cellulare (Layer3)** – frasi, paragrafi:
  - es. gruppi di parole in frasi, blocchi di paragrafo.

- **Livello multicellulare (Layer4+)** – sezioni, capitoli, documenti complessi:
  - es. capitoli di un libro, sezioni specifiche (solo “Lessons Learned”, solo `<body>` HTML, ecc.).

Ogni `SemanticLayer` può lavorare a uno o più di questi livelli, a seconda dei suoi obiettivi.

Esempi:

- `LayerBytes`:
  - Livello atomico: simbolo = byte.
- `LayerVC0` (v2-style):
  - Lavora ancora a livello atomico, ma trasforma il testo in 3 stream distinti (mask, vocali, cons/altri).
- `LayerWords_IT` (v4-style):
  - Livello molecolare: simbolo = parola o blocco non-lettera.
- `LayerLessonsHeader` (idea):
  - Livello multicellulare: rileva e tratta in modo speciale sezioni “Lessons Learned”.

---

## 3. Come mappiamo v1–v4 sull’architettura

L’implementazione attuale è monolitica (tutto in `gcc_huffman.py`), ma possiamo interpretarla così:

### 3.1 Step1 – v1 (byte-level Huffman)

- **Layer concettuale**: `LayerBytes`
  - `encode(data)`:
    - `symbols = list(data)` (byte 0..255),
    - `layer_meta = {"N": len(data)}`.
  - `decode(symbols, layer_meta)`:
    - ricompone i byte.

- **Codec**: `HuffmanCodec` su 256 simboli (byte).

- **Container**: formato v1 (magic, versione 1, `N`, tabella frequenze compatta, lastbits, bitstream).


### 3.2 Step2 – v2 (V/C/O)

- **Layer concettuale**: `LayerVC0`
  - `encode(data)` produce 3 stream:
    - `mask_stream`: V/C/O per ogni byte,
    - `vowels_stream`: tutte le vocali,
    - `cons_stream`: consonanti + altro.
  - `layer_meta` contiene le lunghezze stream e qualsiasi info necessaria.

- **Codec**: `HuffmanCodec` applicato 3 volte (mask, vowels, cons).

- **Container**: formato v2, con:
  - freq e bitstream per mask/vowels/cons,
  - info di lunghezza (`LEN_V`, `LEN_C`, ecc.).

### 3.3 Step3 – v3 (pseudo-sillabe + blocchi)

- **Layer concettuale**: `LayerSyllables_IT`
  - `encode(data)`:
    - tokenizza in pseudo-sillabe (sequenze di lettere spezzate dopo vocale) + blocchi non-lettera,
    - costruisce vocabolario di token → ID 0..K-1,
    - `symbols` = sequenza di ID,
    - `layer_meta = {"vocab": vocabolario, "N_tokens": len(tokens)}`.

- **Codec**: `HuffmanCodec` sugli ID (0..K-1).

- **Container**: formato v3, con:
  - `VOCAB_SIZE`, vocabolario (LEN+TOKEN),
  - `FREQ_ID[VOCAB_SIZE]`, `LASTBITS`, bitstream ID.

### 3.4 Step4 – v4 (parole + blocchi)

- **Layer concettuale**: `LayerWords_IT`
  - `encode(data)`:
    - tokenizza in parole (sequenze di lettere) + blocchi non-lettera,
    - vocabolario parole+blocchi → ID,
    - `symbols` = seq. di ID,
    - `layer_meta = {"vocab": vocabolario, "N_tokens": len(tokens)}`.

- **Codec**: `HuffmanCodec` sugli ID (0..K-1).

- **Container**: formato v4, molto simile a v3, ma con token = parole intere.

---

## 4. Estendibilità: Turco, HTML, “Lessons Learned”, ecc.

Con questa architettura, chiunque può definire un proprio layer, ad esempio:

### 4.1 Esempio: layer per morfemi turchi

```python
class LayerTurkishMorphemes(SemanticLayer):
    id = "tr_morpheme_v1"

    def encode(self, data: bytes):
        text = data.decode("utf-8", errors="ignore")
        tokens, meta = turkish_morphological_analysis(text)
        symbols = serialize_tokens(tokens)   # es. ID interi
        layer_meta = meta                   # info per ricostruire il testo
        return symbols, layer_meta

    def decode(self, symbols, layer_meta) -> bytes:
        tokens = deserialize_tokens(symbols)
        text = turkish_reconstruct(tokens, layer_meta)
        return text.encode("utf-8")
```

Usato con `HuffmanCodec`, il Turco ottiene un compressore “turco-aware” senza toccare il core del progetto.

### 4.2 Esempio: layer per “Lessons Learned”

```python
class LayerLessonsHeader(SemanticLayer):
    id = "lessons_header_v1"

    def encode(self, data: bytes):
        text = data.decode("utf-8", errors="ignore")
        lessons, resto, index_map = estrai_lessons(text)
        symbols = serialize_lessons(resto, lessons)
        layer_meta = {"index_map": index_map}
        return symbols, layer_meta

    def decode(self, symbols, layer_meta) -> bytes:
        resto, lessons = deserialize_lessons(symbols)
        text = rimonta_text(resto, lessons, layer_meta["index_map"])
        return text.encode("utf-8")
```

Il codec non sa nulla di “Lessons Learned”: vede solo `symbols` e fa il suo lavoro.

### 4.3 Esempio: layer HTML `<body>` only

```python
class LayerHtmlBodyOnly(SemanticLayer):
    id = "html_body_v1"

    def encode(self, data: bytes):
        html = data.decode("utf-8", errors="ignore")
        head, body, extra = split_html(html)
        symbols = serialize_body(body)
        layer_meta = {"head": head, "extra": extra}
        return symbols, layer_meta

    def decode(self, symbols, layer_meta) -> bytes:
        body = deserialize_body(symbols)
        html = rebuild_html(layer_meta["head"], body, layer_meta["extra"])
        return html.encode("utf-8")
```

Ancora una volta, l’Engine + Codec vedono solo:

- `LAYER_ID = "html_body_v1"`,
- `CODEC_ID = "huffman"`,
- `PAYLOAD = blob di bytes`.

---

## 5. Che cosa fare del codice esistente (v1–v4)?

L’implementazione attuale (`gcc_huffman.py`) è un prototipo monolitico che:

- implementa Huffman,
- implementa 4 “Step” hardcoded (v1–v4),
- funge sia da layer che da codec che da engine/container.

In termini di architettura, possiamo considerarla come:

- un **proof-of-concept** di:
  - `LayerBytes`, `LayerVC0`, `LayerSyllables_IT`, `LayerWords_IT`,
  - `HuffmanCodec`,
  - container v1–v4.

Due possibili strategie di evoluzione (non mutuamente esclusive):

1. **Trasformare l’attuale repo in “lab Huffman”** e introdurre gradualmente l’architettura modulare:
   - aggiungere nuovi moduli Python:
     - `core/codec_huffman.py`,
     - `layers/bytes.py`, `layers/words_it.py`, ecc.,
     - `engine/container.py`,
   - pian piano migrare v1–v4 verso questa struttura,
   - mantenere compatibilità con i formati v1–v4 almeno per un po’.

2. **Creare un nuovo repo “framework”** e riusare codice dal vecchio:
   - il repo attuale diventa “huffman-compressor-classic”,
   - il nuovo repo espone API pulite per layer/codec/engine,
   - codice e idee di v1–v4 vengono importati e riscritti come plugin.

Quale strada seguire è una decisione progettuale; in entrambi i casi, l’architettura descritta qui resta valida come **modello mentale** per:

- discutere i layer (italiano, turco, HTML, “Lessons Learned”…),
- decidere come integrare nuovi codec,
- ragionare su strategie di auto-tuning (scelta automatica di layer/codec in base al file).

---

## 6. Auto-tuning (accenno)

Una volta separati **Layer** e **Codec**, l’Engine può implementare strategie di scelta automatica, ad esempio:

- analizzare il file (dimensione, percentuale di byte stampabili, pattern linguistici),
- stimare se è:
  - binario generico → `LayerBytes + HuffmanCodec`,
  - testo italiano lungo → `LayerWords_IT + HuffmanCodec`,
  - HTML → `LayerHtmlBodyOnly + HuffmanCodec`, ecc.,
- rispettare preferenze dell’utente:
  - `--profile=latency` vs `--profile=ratio`,
  - `--layer=...` per forzare un layer,
  - `--codec=...` per forzare un codec.

Questo è materiale per sviluppi futuri, ma il design “Layer + Codec + Engine” è pensato proprio per supportare:

- layer semantici personalizzati,
- codec pluggabili,
- e un motore di decisione configurabile o addirittura “intelligente”.
