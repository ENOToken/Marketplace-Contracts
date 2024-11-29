# Guía Completa: Sistema NFT Factory con Proxy

## 1. Despliegue Inicial

### 1.1 Desplegar CustomNFTFactoryV1
1. Compilar `CustomNFTFactoryV1.sol`
2. Desplegar el contrato (sin parámetros)
3. Guardar la dirección: `0x...` (dirección del Factory V1)

### 1.2 Desplegar CustomProxyAdmin
1. Compilar `CustomProxyAdmin.sol`
2. Desplegar el contrato (sin parámetros)
3. Guardar la dirección: `0x...` (dirección del ProxyAdmin)

### 1.3 Desplegar CustomTransparentProxy
1. Compilar `CustomTransparentProxy.sol`
2. Desplegar con estos parámetros:
   - `_logic`: [dirección del Factory V1]
   - `admin_`: [dirección del ProxyAdmin]
   - `_data`: 0x8129fc1c (bytecode de initialize)
3. Guardar la dirección: `0x...` (dirección del Proxy)

## 2. Interactuar con el Factory

### 2.1 Cargar el Factory a través del Proxy
1. En Remix, ir a "Deploy & Run Transactions"
2. En el dropdown de contratos, seleccionar "CustomNFTFactoryV1"
3. En "At Address", pegar la dirección del PROXY
4. Clic en "At Address" - Esto cargará la interfaz del Factory

### 2.2 Crear un NFT
Usar la función `createNFT` con estos parámetros en formato tupla:
```solidity
[
  "Mi NFT Collection",        // nombre
  "MNFT",                    // símbolo
  "0x...",                   // wallet comisión
  "0x...",                   // wallet owner
  "1711399200",             // timestamp inicio (usar epochconverter.com)
  "5",                      // max mints por wallet
  "1000",                   // supply máximo
  "100000000000000000",     // precio (0.1 ETH en wei)
  true,                     // mismo metadata para todos
  "10",                     // comisión (10%)
  "ipfs://..."             // URI de metadata
]
```

## 3. Actualización a V2

### 3.1 Desplegar CustomNFTFactoryV2
1. Compilar `CustomNFTFactoryV2.sol`
2. Desplegar el contrato
3. Guardar la dirección: `0x...` (dirección del Factory V2)

### 3.2 Realizar la Actualización
1. Ir al contrato ProxyAdmin (usar su dirección)
2. Llamar a la función `upgradeTo` con:
   - proxy: [dirección del CustomTransparentProxy]
   - implementation: [dirección del nuevo Factory V2]

### 3.3 Verificar la Actualización
1. Cargar el Factory V2 usando la dirección del PROXY
2. Probar las nuevas funciones como `getVersion()`
3. Verificar que los datos antiguos (NFTs creados) siguen disponibles

## 4. Notas Importantes

### 4.1 Direcciones a Guardar
- Factory V1: `0x...`
- ProxyAdmin: `0x...`
- Proxy: `0x...` (Esta es la dirección principal para interactuar)
- Factory V2: `0x...` (después de actualizar)

### 4.2 Para Interactuar con NFTs Creados
1. Usar la función `getCreatedNFTsPaginated` para obtener direcciones
2. Para cada NFT, cargar el contrato CustomNFT usando su dirección
3. Interactuar con las funciones del NFT (mint, withdraw, etc.)

### 4.3 Verificaciones de Seguridad
- Siempre usar la dirección del PROXY para interactuar
- Guardar backup de las direcciones
- Verificar que el owner del ProxyAdmin es correcto
- Comprobar que initialize() solo se llama una vez

## 5. Troubleshooting

### 5.1 Problemas Comunes
- Si `initialize()` falla: Verificar que no se ha inicializado antes
- Si `upgrade` falla: Verificar que usas el ProxyAdmin correcto
- Si las funciones no aparecen: Verificar que usas el ABI correcto

### 5.2 Verificaciones Post-Actualización
1. `getNumberOfCreatedNFTs()` debe mantener el valor anterior
2. Los NFTs creados deben seguir accesibles
3. Las nuevas funciones deben estar disponibles
4. Los eventos antiguos deben ser visibles

## 6. Mejores Prácticas

1. Siempre hacer pruebas en testnet primero
2. Guardar las direcciones en un lugar seguro
3. Documentar cada actualización
4. Verificar el estado antes y después de actualizaciones
5. Mantener acceso al ProxyAdmin seguro

¿Necesitas que profundice en alguna parte específica de la guía?