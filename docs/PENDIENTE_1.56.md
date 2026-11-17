# Pendiente: llevar Mi Biblioteca (Windows) de Android 1.27 a 1.56

Estado actual: escritorio = Android v1.27 (compilación 1.2.8 #20). Android ya va por la 1.56.
Reglas: nombre «Mi Biblioteca»; las bibliotecas se muestran como «Nube»; subir la versión a 1.56 (Acerca de); un solo build al final.
Al terminar: lista de lo aplicado, lo que no se pudo, y el EXE.

## A. Base (v1.28–1.42)
1. Portadas más fiables (reintentos, varias fuentes, sin repetir las guardadas). «Portadas sugeridas»: guardar en la carpeta del disco sin pisar, con motivo de error visible y reintento.
2. Pantalla de inicio animada con progreso real (sin destello blanco). Copia automática de datos en la nube.
3. Tras subir a la nube, verificar el tamaño del archivo antes de darla por buena.
4. Menú principal: acceso 3D (iconos HD grandes, bien separados, paralaje) y variante 2D con los mismos accesos. Discos y cassettes al doble de tamaño en las bibliotecas. Sin parpadeo de colores/portadas al reconstruir.
5. Cassette: relleno de cinta por bordes. Cinta abierta: velocidad real por carrete.
6. Tocadiscos con el color de la portada (selector de color propio). Ecualizador con medidor analógico con aguja y escala.
7. Aviso de discos nuevos. Fondo de los reproductores según la portada.
8. Explorador de la nube (mover, renombrar, borrar, carpetas sin música).

## B. Iconos del menú (3D girables con el dedo/ratón)
Cada icono es una carpeta de 36 frames WebP 360×360 (00..35, frame 0 = vista frontal) que gira al arrastrar.
Orden: 0 Tocadiscos (technics), 1 Deck (cassette_player), 2 Bandejas DJ (dj), 3 Cinta abierta (melodia), 4 Buscador de portadas / Cover Studio (crate), 5 Buscador de temas y álbumes (lupa), 6 Ajustes (gear), 7 Ecualizador (icono dibujado), 8 iPod (ipod).
Créditos en Acerca de (Sketchfab, CC-BY 4.0): Cassette audio (k7) por Amigos3D; Cassette Case por Geug; Vinyl Record por Cryotizer; engranaje por Alch; Lupa por Maiaraujo. iPod (Scroll Wheel) por Antonio Gomez (CC-BY-NC 4.0, solo uso personal no comercial).
Engranaje: inclinado 65° en X; lupa 70°; elevación 10.
Ajustes (engranaje): el menú desplegable debe poder deslizarse (scroll) para ver todo.

## C. Objetos 3D por disco/cassette (v1.23–1.28, 1.51)
Generar, guardar en la nube y ver con visor propio (vuelta, zoom y desplazamiento). Rehacer objetos. Cola de generación en segundo plano (varios discos a la vez, con progreso, sin bloquear la app).

## D. Contraportada (v1.26, 1.52)
Guardada como «Contraportada» y usada en el visor. Al abrir: usar la original si existe; si no, descargarla (MusicBrainz/Cover Art Archive/Internet Archive); si no, generarla (lista de temas, estilo editable). Se puede cambiar o modificar. Botón «Contraportada» en la ficha del disco.

## E. Línea de tiempo (v1.52)
Pantalla con la biblioteca por años de lanzamiento (año vía MusicBrainz, cacheado). Icono en la barra superior.

## F. Discos personalizados (v1.43, 1.44, 1.47, 1.51)
Discos/cassettes creados con temas de la biblioteca (ids «cust_»). Collage editable de portada con recortes de las portadas de cada tema (formas: rectángulo, redondeado, círculo y retazo rasgado; recorte y zoom ajustables). Estilos: texturas, colores, etiqueta, numeración y sello. Se guardan en la nube. Cajón/biblioteca extra «Personalizados» (sin importar idioma).

## G. iPod (v1.53–1.55)
Reproductor tipo iPod (modo de reproducción nuevo «iPod», menú 8) con rueda de desplazamiento y su icono 3D.

## H. NO incluir (se quitaron en Android)
Vista 3D de los reproductores, Sala de reproductores, Sala de escucha, mini disc, efecto de clima. Si existen en escritorio, eliminarlos.
