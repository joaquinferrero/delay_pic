#!/usr/bin/env perl
#
# Generador de bucles de espera en ensamblador PIC.
# Joaquín Ferrero.
#
# Versión: 2014/06/19
# Primera versión: mayo 2014
#
#  Copyright 2015 Joaquín Ferrero <jferrero@gmail.com>
#  
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#  MA 02110-1301, USA.
#  
# Informar de errores en: jferrero©gmail.com
#

### Bibliotecas ---------------------------------------------------------------
use v5.14;
use utf8::all;				# activa todo el soporte UTF-8
use Getopt::Long;			# interpretación de argumentos
use POSIX qw<locale_h strftime>;	# soporte de localización
use Encode 'decode_utf8';

### Identidad -----------------------------------------------------------------
my $VERSION	= '2015.06.19';
my $AUTOR	= 'Joaquín Ferrero (alias explorer)';


### Inicialización ------------------------------------------------------------
setlocale(LC_TIME, "es_ES");		# configurar salida de fechas en español


### Constantes ----------------------------------------------------------------
my $SUBRUTINA	= 'Espera';		# nombre de la subrutina, por defecto
my $PARAMETRO	= 'd';			# nombre del primer parámetro (se le agregará el número)

my $HZ_CICLO	= 4;			# número de hertzios por ciclo de instrucción
my $START_RAM	= '0x70';		# inicio de la memoria RAM disponible
my $CICLOS_SUB	= 4;			# ciclos generados por la llamada a la subrutina


### Variables -----------------------------------------------------------------
my $arg_verboso	   = 0;			# información del progreso
my $arg_frecuencia = '4Mhz';		# frecuencia de trabajo
my $arg_espera     = '1s';		# espera a generar
my $arg_subrutina;			# nombre de la subrutina

my $frec_hz;				# frecuencia solicitada pasada a Hz
my $espera_ciclos;			# espera solicitada pasada a ciclos de instrucciones
my $espera_ciclos_int;			# lo mismo, pero redondeado
my $espera_generada_segundos;		# espera pasada a segundos

my $ciclos_bucles;			# ciclos de espera generados en los bucles
my $ciclos_generados = 10;		# ciclos de espera que se van a generar (mínimo 10)
my $ciclos_restantes;			# ciclos extra que se pondrán al final
my @d;					# parámetros de los bucles anidados
my $error;				# error cometido con respecto a lo solicitado

					# textos a generar
my $txt_hoy     = decode_utf8 strftime("%c", localtime);
my $txt_cmdline = join " ", $0, @ARGV;
my $txt_cblock  = '';
my $txt_carga   = '';
my $txt_bucles  = '';
my $txt_restos  = '';


### Programa ------------------------------------------------------------------
procesar_argumentos();

saludar()				if $arg_verboso;

$frec_hz       = frecuencia();		# interpretar la frecuencia indicada
$espera_ciclos = espera();		# interpretar la espera solicitada

if ($arg_verboso > 2) {
    say "Reloj:           ", $arg_frecuencia;
    say "Inst./s:         ", $frec_hz / $HZ_CICLO;
    say "Inst. de espera: ", $espera_ciclos;
}

calculo();

generar_codigo_fuente();

salida();


### Subrutinas ----------------------------------------------------------------
sub saludar {
    say 'Generador de bucles de espera en ensamblador PIC';
    say "$AUTOR. $VERSION";
    say;

    if ($arg_verboso > 1) {
        say "Generando código para";
        say "\tFrecuencia: $arg_frecuencia";
        say "\tEspera:     $arg_espera";
        say "\tSubrutina:  $arg_subrutina" if $arg_subrutina;
        say;
    }
}

sub ayuda {
    die <<EOH;
$0 [opciones] <frecuencia[hz|khz|mhz|ghz]> <espera[c|d|h|m|s|ms|us|µs|n]>

Opciones:
    --frequency,-freq	frecuencia de trabajo del microcontrolador
    --frecuencia,-frec	    [hz|khz|mhz|ghz]
    -f
                            ejemplos:
                                 4Mhz  (por defecto)
                                 32K   (abreviado)
                                 32768 (Hz por defecto)

    --delay,-d		espera a generar
    --espera,-e              c:	ciclos (por defecto)
                             d: días
                             h: horas
                             m: minutos
                             s: segundos
                            ms: milisegundos
                            us: microsegundos
                            µs: microsegundos
                            ns: nanosegundos

                            ejemplos:
                                300ms
                                1s      (valor por defecto)
                                8000000

    --subrutine,-s	nombre de la subrutina a generar (opcional)
    --subrutina,-sub	    'Espera' (nombre por defecto)

    --cblock, -c	dirección de comienzo del cblock ($START_RAM)

    --help,-h,-?	mostrar opciones del programa
    --ayuda

    --verbose,-v	muestra más información (acumulativo)
    --verboso
    
Ejemplos:
    $0 16mhz 1ms
    $0 -f 32Mhz -d 1s
    $0 -freq 8Khz --delay 1h
    $0 --frecuencia 32768Hz --espera 12m --subrutina Espera
    $0 -sub Wait_4µs 64Mhz 4µs -c 0x90
EOH
}

sub procesar_argumentos {
    if (!@ARGV) {
        push @ARGV, '-h';			# mostrar la ayuda, por defecto
    }

    exit if not GetOptions(
        'help|ayuda|?'			=> \&ayuda,
        'verboso|verbose+'		=> \$arg_verboso,
        'frecuencia|frequency=s'	=> \$arg_frecuencia,
        'espera|delay=s'		=> \$arg_espera,
        'subrutine|subrutina:s'		=> \$arg_subrutina,
        'cblock=s'			=> \$START_RAM,
    );

    if ($arg_verboso > 2) {
        say "Argumentos: [@ARGV]";
    }

    if (@ARGV == 2) {
        ($arg_frecuencia, $arg_espera) = @ARGV;
    }

    if (defined $arg_subrutina) {		# caso de cadena vacía para la subrutina
        $arg_subrutina = $SUBRUTINA if not $arg_subrutina;
    }

}

sub frecuencia {
    ## Convertir la frecuencia de trabajo indicada a Hz
    my $multiple = 1;
    my $frec_hz  = lc $arg_frecuencia;

    if ( $frec_hz =~ /(\w)hz$/i ) {
        $multiple = 10 ** ( 3 * ( 1 + index 'kmg', $1 ) );
    }

    $frec_hz = ( 0+ $frec_hz) * $multiple;
}

sub espera {
    ## Pasar la espera indicada a ciclos de instrucciones
    my $espera_solicitada = lc $arg_espera;
    my $espera_ciclos;
    my $multiplicador = 1;
    my $txt_retraso;

    if ( $espera_solicitada =~ /(\d+)([cdhmsuµn]+)?$/ ) {
        my $ciclos = $1;
        my $sufijo = $2 // 'c';		# por defecto, ciclos de procesador
           $sufijo =~ tr/µ/u/;		# simplificar los casos

        $multiplicador
        	= ($sufijo eq 'c') ? 1                  # ciclos de procesador
		: ($sufijo eq 'd') ? $frec_hz * 86_400  # días
		: ($sufijo eq 'h') ? $frec_hz * 3_600   # horas
		: ($sufijo eq 'm') ? $frec_hz * 60      # minutos
		: ($sufijo eq 's') ? $frec_hz           # segundos
                					# fracciones de segundo
		: $frec_hz * ( 10 ** ( -3 * ( 1 + index 'mun', substr $sufijo, 0, 1 ) ) )
		;

        $multiplicador /= $HZ_CICLO if $sufijo ne 'c';
        $espera_ciclos = ( 0+ $espera_solicitada) * $multiplicador;

        if ( $sufijo eq 'c' ) {
            $arg_espera += 0;
            $arg_espera = "${arg_espera}ciclos de instrucción";
        }
    }
    else {
        ayuda();
        exit 1;
    }

    $espera_ciclos_int  = int($espera_ciclos + 0.5);
    $espera_ciclos_int -= $CICLOS_SUB if $arg_subrutina;

    if ($arg_verboso > 2) {
        say;
        say "Retraso en ciclos: $espera_solicitada";
        say "Redondeo ciclos: $espera_ciclos_int";

        if ( $espera_ciclos_int == 0 ) {
            printf "Error: %f %%\n", 100 * $espera_ciclos;
        }
        else {
            printf "Error: %f %%\n", 100 * ( 1 - $espera_ciclos_int / $espera_ciclos );
        }
    }
    
    $espera_ciclos;
}

sub calculo {
    ## Cálculo de las instrucciones a generar
    my $nbucles       = 0;			# número de bucles anidados
    $ciclos_bucles    = 0;			# ciclos generados en la carga más en los bucles
    $ciclos_restantes = $espera_ciclos_int;	# ciclos que se generan al final

    while ( $ciclos_generados < $espera_ciclos_int ) {
        $nbucles++;				# probamos un bucle más

        ## Parámetros según el número de bucles
        my $ciclos_carga              = $nbucles * 2;
        my $ciclos_final_bucles       = $nbucles * 2;
        my $ciclos_bucle_interno      = $nbucles * 2 + 1;
        my $ciclos_carga_y_bucles_min = $ciclos_carga + $ciclos_final_bucles;
        my $ciclos_bucles_anidados    = $espera_ciclos_int - ($ciclos_carga_y_bucles_min);
        my $vueltas_bucle_interno     = int( $ciclos_bucles_anidados / $ciclos_bucle_interno );
        $ciclos_restantes             = $ciclos_bucles_anidados % $ciclos_bucle_interno;

        if ($arg_verboso > 2) {
            say;
            say "bucles:                    $nbucles";
            say "ciclos_carga:              $ciclos_carga";
            say "ciclos_final_bucles:       $ciclos_final_bucles";
            say "ciclos_bucle_interno:      $ciclos_bucle_interno";
            say "ciclos_carga_y_bucles_min: $ciclos_carga_y_bucles_min";
            say "ciclos_bucles_anidados:    $ciclos_bucles_anidados";
            say "vueltas_bucle_interno:     $vueltas_bucle_interno";
            say "resto:                     $ciclos_restantes";
        }

        ## Cálculo de parámetros de los bucles y ciclos que se han generado realmente
        $ciclos_bucles = 0;
        @d = ();
        my $div = 1;
        for my $d (1 .. $nbucles) {
            my $v = int( $vueltas_bucle_interno / $div ) % 256;
            push @d, ($v + 1) % 256;
            $ciclos_bucles += $v * $div;
            $div *= 256;
        }

        $ciclos_bucles *= $ciclos_bucle_interno;
        $ciclos_bucles += $ciclos_carga + $ciclos_final_bucles;

        $ciclos_generados = $ciclos_bucles + $ciclos_restantes;

        if ($arg_verboso > 2) {
            say "parámetros:                @d";
            say "ciclos_bucles:             $ciclos_bucles";
        }
    }

    if ($ciclos_bucles == 0) {
        $ciclos_generados = $espera_ciclos_int;
    }

    $ciclos_generados += $CICLOS_SUB if $arg_subrutina;

    if ($arg_verboso > 2) {
        say;
        say "Bucles anidados:           $nbucles";
        say "Ciclos bucles:             $ciclos_bucles";
        say "Parámetros:                @d";
        say "Resto:                     $ciclos_restantes";
        say "Ciclos generados           $ciclos_generados";
    }
}

sub generar_codigo_fuente {
    ### Generar código fuente
    $espera_generada_segundos = $ciclos_generados / ( $frec_hz / $HZ_CICLO );
    $error = $espera_ciclos_int ? sprintf "%4.02f %%", 100 * abs( $ciclos_generados - $espera_ciclos_int - ($CICLOS_SUB * ($arg_subrutina ne ''))) / $espera_ciclos_int
           :			  '0.00 %'
           ;

    if ($arg_subrutina) {
        $txt_carga .= "$arg_subrutina:\n";
        $PARAMETRO  = "${arg_subrutina}_$PARAMETRO";
    }

    my $indice_parametro = 1;

    if (@d) {					# si al menos tenemos un bucle anidado
        my $etiqueta = 'Espera_0';
        $etiqueta    = "${arg_subrutina}_loop" if $arg_subrutina;
        $txt_cblock .= "\tcblock $START_RAM\n";	# declaramos zona de variables
        $txt_bucles .= "\n$etiqueta:\n";
        $txt_carga  .= "\t\t\t\t\t;$ciclos_bucles ciclos\n";

        for my $i ( 0 .. $#d ) {
            my $j = $i + 1;
            $txt_cblock .= "\t\t$PARAMETRO$indice_parametro\n";
            $txt_carga  .= "\t\tmovlw\t" . sprintf( "0x%02X", $d[$i] ) . "\n";
            $txt_carga  .= "\t\tmovwf\t$PARAMETRO$indice_parametro\n";
            $txt_bucles .= "\t\tdecfsz\t$PARAMETRO$indice_parametro, f\n";
            $txt_bucles .= "\t\tgoto\t\$+2\n";
            $indice_parametro++;
        }
        $txt_cblock .= "\tendc";
        $txt_bucles =~ s/\$\+2$/$etiqueta/;
    }

    if ($ciclos_restantes) {			# si hay un resto de ciclos por generar
        $txt_restos = "\t\t\t\t\t;$ciclos_restantes ciclos\n";
        while ( $ciclos_restantes >= 2 ) {
            $txt_restos .= "\t\tgoto\t\$+1\n";
            $ciclos_restantes -= 2;
        }
        while ( $ciclos_restantes-- ) {
            $txt_restos .= "\t\tnop\n";
        }
    }

    if ($arg_subrutina) {
        $txt_restos .= "\n\t\t\t\t\t;4 ciclos (incluyendo la llamada)\n";
        $txt_restos .= "\t\treturn\n";
    }

    chomp($txt_carga, $txt_bucles, $txt_restos);
}

sub salida {
    ### Salida al exterior
    for ($arg_espera, $arg_frecuencia) {
        s/(?<=\d)(?=\D)/ /;
    }

    print <<EOT;
; ---------------------------------------------------------------------------
; Espera = $arg_espera
; Frecuencia de reloj = $arg_frecuencia
; Espera real = $espera_generada_segundos segundos = $ciclos_generados ciclos
; Error = $error
; ---------------------------------------------------------------------------

$txt_cblock

$txt_carga
$txt_bucles

$txt_restos

; ---------------------------------------------------------------------------
; $txt_cmdline
; Generado por delay_pic.pl (Joaquín Ferrero, $VERSION) $txt_hoy
; http://perlenespanol.com/foro/generador-de-codigos-de-retardo-para-microcontroladores-pic-t8602.html
; ---------------------------------------------------------------------------
EOT
}

__END__
