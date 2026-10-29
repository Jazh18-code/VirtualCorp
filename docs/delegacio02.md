# VirtualCorp – Delegació 02 (jhoanluisaduvirifp25)

Responsable: Jhoan Luis Aduviri Zambrana · Rang assignat: **10.2.0.0/16**

Aquest document recull el disseny de xarxa de la delegació, les decisions preses
en adaptar el repositori inicial i la validació de l'Activitat 1 (desplegament
dels quatre routers MikroTik).

## 1. Disseny de xarxa

### 1.1 Zones i subxarxes

| Zona | Subxarxa | Passarel·la | Router |
|---|---|---|---|
| Planta baixa – zona general (consergeria, expo1–4 .33–.36) | 10.2.0.0/25 | 10.2.0.1 | mikrotik1 |
| Planta baixa – zona privada / CPD (pve01 .133, dbsrv .134, infosrv .135) | 10.2.0.128/26 | 10.2.0.129 | mikrotik0 |
| Planta baixa – DMZ (websrv .197) | 10.2.0.192/27 | 10.2.0.193 | mikrotik0 |
| Enllaç router0–router1 | 10.2.0.224/30 | – | mikrotik0/1 |
| Enllaç router1–router2 | 10.2.0.228/30 | – | mikrotik1/2 |
| Enllaç router2–router3 | 10.2.0.232/30 | – | mikrotik2/3 |
| Planta 1 – desenvolupament | 10.2.1.0/24 | 10.2.1.1 | mikrotik2 |
| Planta 2 – desenvolupament | 10.2.2.0/24 | 10.2.2.1 | mikrotik2 |
| Planta 3 – departaments corporatius | 10.2.3.0/25 | 10.2.3.1 | mikrotik3 |
| Planta 3 – direcció (xarxa aïllada) | 10.2.3.128/25 | 10.2.3.129 | mikrotik3 |

Les impressores (10.2.n.65) queden dins de la subxarxa de cada planta
(10.2.3.65 és dins de 10.2.3.0/25). Lliure per a ampliacions: 10.2.0.236–10.2.0.255
i 10.2.4.0–10.2.255.255.

### 1.2 Routers i interfícies

Els routers `router0..3` de l'enunciat s'implementen com les VM `mikrotik0..3`
(nom usat pel repositori inicial i com a *identity* de RouterOS).

| Router | ether1 | ether2 | ether3 | ether4 | ether5 |
|---|---|---|---|---|---|
| mikrotik0 | ISP (NAT VirtualBox, DHCP 10.0.2.15) | r0-r1 10.2.0.225/30 | dmz 10.2.0.193/27 | privada 10.2.0.129/26 | – |
| mikrotik1 | (sense ús) | r0-r1 10.2.0.226/30 | r1-r2 10.2.0.229/30 | pl0 10.2.0.1/25 | – |
| mikrotik2 | (sense ús) | r1-r2 10.2.0.230/30 | r2-r3 10.2.0.233/30 | pl1 10.2.1.1/24 | pl2 10.2.2.1/24 |
| mikrotik3 | (sense ús) | r2-r3 10.2.0.234/30 | pl3 10.2.3.1/25 | pl3-direccio 10.2.3.129/25 | – |

Cada nom de la columna és la xarxa interna de VirtualBox (`intnet`) a la qual
està connectada la NIC.

```
 Internet
    │ (NAT VirtualBox 10.0.2.0/24)
 ┌──┴────────┐ 10.2.0.224/30 ┌───────────┐ 10.2.0.228/30 ┌───────────┐ 10.2.0.232/30 ┌───────────┐
 │ mikrotik0 ├───────────────┤ mikrotik1 ├───────────────┤ mikrotik2 ├───────────────┤ mikrotik3 │
 └─┬───────┬─┘ .225     .226 └─────┬─────┘ .229     .230 └──┬─────┬──┘ .233     .234 └──┬─────┬──┘
   │       │                       │                        │     │                     │     │
  DMZ   Privada/CPD            Planta 0                 Planta 1 Planta 2          Planta 3  Direcció
 .192/27  .128/26              .0/25                   10.2.1/24 10.2.2/24         .3.0/25  .3.128/25
```

### 1.3 Encaminament, NAT i DNS

- **RIP v2** (instància `rip1`, redistribueix connectades) a totes les interfícies
  internes: cada router aprèn totes les subxarxes de la delegació.
- **Ruta per defecte** estàtica cap al router anterior de la cadena
  (mikrotik3 → .233, mikrotik2 → .229, mikrotik1 → .225); mikrotik0 l'obté per DHCP de l'ISP.
- **NAT**: `masquerade` a mikrotik0 per ether1 (únic punt de sortida a Internet).
- **DNS**: mikrotik0 rep els DNS de l'ISP i fa de resolutor (`allow-remote-requests`)
  per als altres routers (`servers=10.2.0.225`). Les consultes DNS que arriben per
  ether1 (ISP) es descarten al tallafoc.

## 2. Accés SSH

| Usuari | Clau | Ús |
|---|---|---|
| `sysadmin` | `configs/ssh/vcorp_sysadmin.pub` (privada a `~/.ssh/vcorp_sysadmin`, mai al repo) | Administració i automatització |
| `auditor` | `configs/ssh/vcorp_auditor.pub` (clau del professor, sense modificar) | Accés administratiu del professor |
| `admin` | – | **Deshabilitat** (per defecte no tenia contrasenya) |

L'usuari `auditor` té una contrasenya aleatòria que no es desa enlloc: només s'hi
pot accedir amb la clau del professor.

Accés des del host: mikrotik0 per `127.0.0.1:2200`; la resta, a través de mikrotik0
(ProxyJump), per la seva adreça de trànsit:

```bash
ssh -i ~/.ssh/vcorp_sysadmin -p 2200 sysadmin@127.0.0.1
ssh -i ~/.ssh/vcorp_sysadmin -J sysadmin@127.0.0.1:2200 sysadmin@10.2.0.226
```

(per al professor, el mateix amb `-i vcorp_auditor` i l'usuari `auditor`.)

## 3. Desplegament reproduïble

```bash
cp .env.example .env      # DELEGATION_ID ?= 2
make ssh-keys             # genera vcorp_sysadmin (no toca vcorp_auditor.pub)
make deploy-routers       # crea i configura mikrotik0..3
make validate             # proves de connectivitat, Internet i SSH
make validate-reboot      # el mateix després de reiniciar (persistència)
```

Per a una altra delegació només cal canviar `DELEGATION_ID` a `.env`.

## 4. Decisions i problemes resolts

| # | Problema detectat | Causa | Solució |
|---|---|---|---|
| 1 | Adreces 10.1.x.x a `deploy_routers.sh` | El repo inicial té l'adreçament de Serveis Centrals | Adreces parametritzades amb `DELEGATION_ID`/`NET_PREFIX` (`.env`) |
| 2 | La zona privada 10.2.0.128/26 (CPD) no tenia passarel·la | El disseny inicial no l'assignava a cap router | Nova interfície `privada` 10.2.0.129/26 a mikrotik0, al costat de la DMZ i l'ISP, perquè el router de frontera controli tot el tràfic del CPD |
| 3 | `make ssh-keys` generava una clau `vcorp_auditor` nova i sobreescrivia la del professor | El script tractava l'auditor com una clau pròpia | Ja no es genera; el script comprova que existeix la clau publicada |
| 4 | La clau del professor no s'instal·lava als routers | El bootstrap només instal·lava `sysadmin` | Bootstrap crea l'usuari `auditor` (grup full) i n'importa la clau |
| 5 | `log_error: orden no encontrada` en camins d'error | Funció no definida (només existia `log_err`) | `log_error` definit a `common.sh` |
| 6 | Fallada intermitent: `input does not match any value of public-key-file` a mikrotik1 | RouterOS triga uns segons a registrar el fitxer pujat amb `scp` | Funció `import_ssh_key` amb reintents (10 × 2 s) |
| 7 | Els routers 1–3 no podien resoldre noms | Sense servidor DNS configurat | mikrotik0 com a resolutor; `--dns` a la resta |
| 8 | Usuari `admin` sense contrasenya | Configuració de fàbrica de CHR | `/user disable admin` un cop instal·lades les claus |
| 9 | Routers 1–3 no accessibles des del host | La seva NIC1 deixa el NAT després del bootstrap | Reenviament SSH a mikrotik0 (`forwarding-enabled=local`) i accés per ProxyJump |
| 10 | La prova de persistència no reiniciava mikrotik1–3 (uptime no es reiniciava) | Es reiniciava primer mikrotik0, que és el salt SSH cap als altres | Reinici en ordre invers (mikrotik3 → mikrotik0); es verifica amb l'uptime |
| 11 | Host: `apt` fallava i VirtualBox no carregava | Font `cdrom` obsoleta i Secure Boot actiu (ASUS no permet inscriure la MOK) | Font `cdrom` desactivada; Secure Boot desactivat a la BIOS |

## 5. Validació

Evidències generades automàticament (sortida real dels routers):

- [`evidencies/validacio.txt`](evidencies/validacio.txt) – `make validate` després del desplegament.
- [`evidencies/validacio-reinici.txt`](evidencies/validacio-reinici.txt) – `make validate-reboot`
  (els quatre routers reiniciats; uptime < 2 min).

| Comprovació | mikrotik0 | mikrotik1 | mikrotik2 | mikrotik3 |
|---|---|---|---|---|
| Identity, adreces i màscares segons el disseny | OK | OK | OK | OK |
| Ping als altres tres routers (0 % pèrdua) | OK | OK | OK | OK |
| Ping 1.1.1.1 | OK | OK | OK | OK |
| Resolució i ping de www.google.com | OK | OK | OK | OK |
| SSH personal (`sysadmin` + `vcorp_sysadmin`) | OK | OK | OK | OK |
| Clau del professor a l'usuari `auditor` | OK | OK | OK | OK |
| `admin` deshabilitat | OK | OK | OK | OK |
| Configuració persistent després de reiniciar | OK | OK | OK | OK |

La clau privada del professor no està disponible a l'alumne, per tant l'accés
de l'auditor es verifica comprovant que la seva clau pública està importada a
l'usuari `auditor` (grup `full`) de cada router; l'usuari pot entrar-hi amb:
`ssh -i vcorp_auditor -J auditor@<host>:2200 auditor@10.2.0.226`.
