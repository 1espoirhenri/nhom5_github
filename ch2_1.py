from gpiozero import LED, Button
from signal import pause

button = Button(23)
red = LED(14)
amber = LED(15)
green = LED(18)

leds = [green, amber, red]
idx = 0

def change_led():
    global idx 

    leds[idx].off()
    idx = (idx + 1) % len(leds)
    leds[idx].on()

leds[idx].on()
button.when_pressed = change_led
pause()
