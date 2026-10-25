# Official game terms in the eight languages

Translations of MogHub and its plugins use the words FINAL FANTASY RESONANCE itself uses, so a player meets the
same term in a mod as in the game. These are taken from the game's own text (`Game.locres` for each culture,
extracted with `plugins/bestiary/tools/ffr-dump locres <culture>`), not translated by hand.

Culture codes (the names of the lang files): `en`, `fr`, `de`, `es`, `ja`, `ko`, `zh-Hans`, `zh-Hant`.

Where the game has a word, a plugin can also take it at run time with `kit.game.text(table, key)`, and it will be
right in every language, including future ones.

| English | French | German | Spanish | Japanese | Korean | Simplified Chinese | Traditional Chinese |
|---|---|---|---|---|---|---|---|
| Libra (the scan) | Acuité | Analyse | Libra | ライブラ | 라이브라 | 分析 | 窺伺探測 |
| Vision / Visions | Vision / Visions | Vision / Visionen | Visión / Visiones | ビジョン | 비전 | 幻兵 | 幻兵 |
| Mastery Rank | rang de maîtrise | Meisterschaftsrang | rango de dominio | MASTERY RANK | MASTERY RANK | MASTERY RANK | MASTERY RANK |
| Awakening level | niveau d'éveil | Erwachensstufe | despertar | 覚醒度 | 각성도 | 觉醒度 | 覺醒度 |
| Awaken | Éveil | Erwecken | Despertar | 覚醒する | 각성하기 | 觉醒 | 覺醒 |
| Limit Burst | Limite | Limitrausch | Estallido límite | リミットバースト | 리미트 버스트 | 极限技 | 極限技 |
| Gil | gils | Gil | guiles | ギル | 길 | 金币 | GIL |
| EXP | EXP | EP | EXP | EXP | EXP | 经验值 | EXP |
| MRP | PRM | MSP | PD | MRP | MRP | MRP | MRP |
| AP | PA | FP | PH | AP | AP | AP | AP |
| HP | PV | LP | VIT | HP | HP | 生命值 | HP |
| MP | PM | MP | PM | MP | MP | 法力值 | MP |
| Items | Objets | Gegenstände | Objetos | アイテム | 아이템 | 道具 | 道具 |
| Consumables | Consommables | Mittel | Consumibles | 消耗品 | 소모품 | 消耗品 | 消耗品 |
| Equipment | Équipement | Ausrüstung | Equipo | 装備 | 장비 | 装备 | 裝備 |
| Weapons / Armor / Accessories | Armes / Armures / Accessoires | Waffen / Rüstung / Accessoires | Armas / Armaduras / Accesorios | 武器 / 防具 / アクセサリ | 무기 / 방어구 / 장신구 | 武器 / 防具 / 饰品 | 武器 / 防具 / 飾品 |
| Artifacts | Artéfacts | Artefakte | Artefactos | アーティファクト | 아티팩트 | 古遗物 | 古遺物 |
| Abilities | Aptitudes | Fähigkeiten | Habilidades | アビリティ | 어빌리티 | 能力 | 能力 |
| Magic | Magie | Magie | Magia | まほう | 마법 | 魔法 | 魔法 |
| Shop | Boutique | Laden | Mercader | SHOP | SHOP | 商店 | 商店 |
| Buy / Sell / Price | Acheter / Vendre / Prix | Kaufen / Verkaufen / Preis | Comprar / Vender / Precio | 買う / 売る / 値段 | 산다 / 판매 / 가격 | 购买 / 出售 / 价格 | 購買 / 出售 / 價格 |
| World Map | Mappemonde | Weltkarte | Mapamundi | 世界地図 | 세계 지도 | 世界地图 | 世界地圖 |
| Party | Groupe | Gruppe | Grupo | パーティ | 파티 | 队伍 | 隊伍 |
| Enemy / enemies | ennemi(s) | Gegner | enemigo(s) | 敵 | 적 | 敌人 | 敵人 |
| Steal | Vol | Stehlen | Robar | ぬすむ | 훔치기 | 偷窃 | 偷竊 |
| Rare drop / Rare stealable | Butin rare / Objet rare à voler | Belohnung+ / Stehlbares+ | Botín raro / Robo raro | ドロップ(レア) / ぬすむ(レア) | 드롭(레어) / 훔치기(레어) | 掉落（稀有） / 偷窃（稀有） | 掉落（稀有） / 偷竊（稀有） |
| Escape | Fuite | Fliehen | Huir | 逃げる | 도주 | 逃走 | 逃跑 |
| Random encounters | combats aléatoires | Zufallsbegegnungen | encuentros | エンカウント | 인카운트 | 遇敌 | 遇敵 |
| Battle | Combat | Kampf | Batalla | バトル | 배틀 | 战斗 | 戰鬥 |
| Battle speed | vitesse des combats | Kampftempo | velocidad de combate | バトルスピード | 배틀 속도 | 战斗速度 | 戰鬥速度 |
| Auto | Auto | Automatisch | Automático | オート | 자동 | 自动 | 自動 |
| Field | Terrain | Feld | Campo | フィールド | 필드 | 野外 | 野外 |
| Rewards | Récompenses | Belohnungen | Recompensas | 報酬 | 보상 | 报酬 | 報酬 |
| Level / Lv. | Niveau / Niv. | Stufe / St. | Nivel / Nv. | レベル / Lv | 레벨 / Lv. | 等级 / Lv | 等級 / Lv |
| Weak / Resisted / Absorbed | Faiblesse / Résistance / Absorption | Schwäche / Widerstanden / Absorbiert | Débil / Resiste / Absorbe | Weak / Resist / Absorb | Weak / Resist / Absorb | Weak / Resist / Absorb | Weak / Resist / Absorb |
| Weaknesses | Faiblesses | Schwächen | Debilidades | 弱点 | 약점 | 弱点 | 弱點 |
| Status ailments | Altérations d'état | Zustände | Estados alterados | 状態異常 | 상태이상 | 状态异常 | 狀態異常 |
| Stagger (break) | choc | Schock | aturdir | ブレイク | 브레이크 | 破防 | 擊潰 |
| Difficulty | Difficulté | Schwierigkeitsgrad | Dificultad | 難易度 | 난이도 | 难易度 | 難易度 |
| Tablet Shards | Fragments de tablette | Tafelfragmente | Fragmentos de tablilla | 石板のカケラ | 석판 조각 | 石板碎片 | 石板碎片 |
| Treasure Chest | Coffre au trésor | Schatztruhe | Cofre | 宝箱 | 보물상자 | 宝箱 | 寶箱 |
| Main Menu | Menu principal | Hauptmenü | Menú principal | メインメニュー | 메인 메뉴 | 主菜单 | 主選單 |
| Options | Options | Einstellungen | Opciones | OPTION | OPTION | OPTION | OPTION |
| On / Off | Oui / Non | An / Aus | Sí / No | オン / オフ | ON / OFF | 开 / 关 | 開 / 關 |
| Reset | Réinitialiser | Zurücksetzen | Restablecer | リセット | 초기화 | 重置 | 重置 |
| Default | Par défaut | Standard | Por defecto | デフォルト | 초기 설정 | 默认 | 預設 |
| Confirm / Back | Confirmer / Retour | Bestätigen / Zurück | Confirmar / Atrás | 決定 / もどる | 결정 / 뒤로 | 确定 / 返回 | 決定 / 返回 |
| Text language | Langue du texte | Textsprache | Idioma de los textos | テキスト言語 | 텍스트 언어 | 文本语言 | 文字語系 |

Notes:
- The French, German and Spanish games translate many terms that the Asian versions keep in English (Libra is
  *Acuité* / *Analyse*; HP is *PV* / *LP* / *VIT*).
- Japanese uses hiragana for some classic command names (ぬすむ, まほう, もどる): keep them.
- The game's own On / Off for options in French and Spanish are *Oui / Non* and *Sí / No*.
