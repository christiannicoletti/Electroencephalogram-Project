//---------------------------------Imports-------------------------------------------------
import processing.serial.*;
import ddf.minim.*;
import ddf.minim.analysis.*;
import ddf.minim.effects.*;

//-------------------------Initialization of Variables--------------------------------------
int timeScale = 50; // Scales the amplitude of time-domain data
static int normalScale = 50;
static int freqAvgScale = 50; // Does same for averages of frequency data
static int alphaCenter = 12;
static int alphaBandwidth = 2; // Actually bandwidth divided by 2
static int betaCenter = 24;
static int betaBandwidth = 2;
static int NUM_CHANNELS = 2;
int seconds = 2; // How many seconds of data to display / analyze at once
int fRate = 60;
int inBuffer = 4; // How many data points to take in at once, this*60 = sampling rate
float displayBuffer[][] = new float[NUM_CHANNELS][fRate * inBuffer * seconds];
float timeLength = displayBuffer[0].length; // Number of samples/sec in time 

// Variables used to store data functions/effects.
Minim minim;
AudioInput in;
Serial myPort;
float[] timeSignal = new float[240];
FFT fft;
NotchFilter notch;
LowPassSP lpSP;
LowPassFS lpFS;
HighPassSP hpSP;
BandPass betaFilter;
BandPass alphaFilter;

// Constants mainly used for scaling the data to readable sizes
int windowWidth = 840;
int windowHeight = 500;
int FFTheight;
float scaling[] = {
 .00202,
 .002449 / 2,
 .0075502 / 2,
 .00589,
 .008864,
 .01777
};
int FFTrectWidth = 18;
float scaleFreq = 1.33f;
float timeDomainAverage = 0;

// Variables used to handle bad data
int cutoffHeight = 200; // Frequency height to throw out "bad data" for averaging after
float absoluteCutoff = 1.5;
boolean absoluteBadDataFlag; //  Data that is bad because it's way too far out of our desired range --
                             //  ex: shaking your head for a second
boolean averageBadDataFlag; //  Data that's bad because it spikes too far outside of the average for 
                            //  that second -- 
                            //  ex: blinking your eyes for a split second

// Constants used to create a running average of the data.
float[][] averages;
int averageLength = 200; // Averages about the last 5 seconds worth of data
int averageBins = 6; // 6 types of brain waves
int counter = 0;

//--------------------------Functions------------------------------------------------------
void setup() {
    // Initialize 2D array of averages for running average calculation
    averages = new float[averageBins][averageLength];
    for (int i = 0; i < averageBins; i++) {
        for (int j = 0; j < averageLength; j++) {
            averages[i][j] = 0;
        }
    }
    
    // Initialize array used for input
    for (int i = 0; i < 240; i++) {
        timeSignal[i] = 0;
    }

    // Set drawing parameters
    FFTheight = windowHeight - 200;

    // Setting size of window interface
    surface.setSize(windowWidth, windowHeight);

    // Initialize minim and filter objects
    minim = new Minim(this);
    lpSP = new LowPassSP(31, 32768);
    lpFS = new LowPassFS(60, 32768);
    hpSP = new HighPassSP(7, 32768);
    notch = new NotchFilter(60, 10, 32768);
    betaFilter = new BandPass(betaCenter / scaleFreq, betaBandwidth / scaleFreq, 32768);
    alphaFilter = new BandPass(alphaCenter / scaleFreq, alphaBandwidth / scaleFreq, 32768);
    
    // Turn on debug messages and initialize LineIn specifications
    minim.debugOn();
    
    // Defining minim input with filters
    in = minim.getLineIn(Minim.MONO, 32768, 44100, 16); // (type, bufferSize, sampleRate, bitDepth)
    in.addEffect(lpSP);
    in.addEffect(lpFS);
    in.addEffect(hpSP);
    in.addEffect(notch);
    in.addEffect(alphaFilter);
    in.addEffect(betaFilter);
    
    // Initialize FFT
    // Frame size of 4,096 samples gives us 2048 frequency bands
    // This gives a bin width of ~21 Hz (giving worse resolution at low freq and better at high freq)
    fft = new FFT(in.bufferSize(), 4096/2);
    fft.window(FFT.HAMMING); // Default: Hamming enabled
    rectMode(CORNERS);
}

void draw() {
    /* badDataFlag handles any "artifacts" we may pick up while recording the data.
    Artifacts are essentially imperfections in the data recording -- they can come
    from muscle movements, blinking, anything that disturbs the electrodes. If the 
    program encounters a set of data that spikes out of a reasonable window 
    (controlled by the variable cutoffHeight), it won't consider that data
    when computing the running average.
    */
    absoluteBadDataFlag = false;
    averageBadDataFlag = false;

    background(0); // Make sure the background color is black
    stroke(255); // Time data is drawn in white

    line(0, 100, windowWidth, 100); // Line separating time and frequency data

    drawSignalData();

    // Check for spikes relative to other data
    for (int i = 0; i < windowWidth - 1; i++) {
        if (abs( in .left.get((i + 1) * round( in .bufferSize() / windowWidth))) > timeDomainAverage * 4) {
            averageBadDataFlag = true;
        }
    }

    displayText();

    displayFreqAverages();

    counter++;
}

// Used for comparing the difference of hamming and lack of hamming
void keyPressed() {
    if (key == 'w') {
        fft.window(FFT.HAMMING);
    }
    if (key == 'e') {
        fft.window(FFT.NONE);
    }
}

// While there are bytes to use, shift the timeSignal array backwards
void serialEvent(Serial p) {
    while (p.available() > 0) { // While bytes available
        shiftNtimes(timeSignal, 1);
    }
}

// Shifts all elements in myArray numShifts times left, resulting in the 
// [0-numShift] elements being pushed off, and the last numShift elements
// becoming zero. Does this for all data channels.
public void shiftNtimes(float[] myArray, int numShifts) {
    int timesShifted = 0;
    while (timesShifted < numShifts) {
        for (int i = 0; i < timeLength - 1; i++) {
            myArray[i] = myArray[i + 1];
        }
    myArray[(int) timeLength - 1] = 0;
    timesShifted++;
    }
}

// Draw the signal in time and frequency
void drawSignalData() {
  
    fft.forward(in.left);
    
    for (int i = 0; i < windowWidth - 1; i++) {
        stroke(255, 255, 255); // Draw signal frequency in white

        // Data that fills our window is normalized to +-1, so we want to throw out
        // sets that have data that exceed this by the factor absoluteCutoff
        if (abs( in .left.get(i * round( in .bufferSize() / windowWidth))) * timeScale / normalScale > .95) {
            absoluteBadDataFlag = true;
            fill(255, 255, 255);
            stroke(150, 150, 150);
        }
    
        // Draw the time domain signal (x1, y1, x2, y2) 
        // "50 +" simply keeps the data centered in the screen
        line(i, 50 + in .left.get(i * round( in .bufferSize() / windowWidth)) * timeScale,
        i + 1, 50 + in .left.get((i + 1) * round( in .bufferSize() / windowWidth)) * timeScale);
        
        // Adding to the time domain average the power spectrum of the audioInput at i
        timeDomainAverage += abs( in .left.get(i * round( in .bufferSize() / windowWidth))); //<>//
        
        // Draw un-averaged frequency bands of signal
        if (i < (windowWidth - 1) / 2) {
            // Set colors for each type of brain wave
            if (i <= round(3 / scaleFreq)) {
                fill(250, 0, 0); // Delta (Red) (~1-4 Hz)
                stroke(255, 0, 10);
            }
            if (i >= round(4 / scaleFreq) &&
            i <= round((alphaCenter - alphaBandwidth) / scaleFreq) - 1) {
                fill(200, 0, 50); // Theta (Red) (~4-7 Hz)
                stroke(225, 0, 25);
            }
            if (i >= round((alphaCenter - alphaBandwidth) / scaleFreq) &&
            i <= round((alphaCenter + alphaBandwidth) / scaleFreq)) {
                fill(150, 0, 100); // Alpha (Red - Light Purple) (~7-12 Hz)
                stroke(175, 0, 75);
            }
            if (i >= round((alphaCenter + alphaBandwidth) / scaleFreq) + 1 &&
            i <= round((betaCenter - betaBandwidth) / scaleFreq) - 1) {
                fill(100, 0, 150); // Low Beta (Light Purple - Purple)) (~12-16 Hz)
                stroke(125, 0, 125);
            }
            if (i >= round((betaCenter - betaBandwidth) / scaleFreq) &&
            i <= round((betaCenter + betaBandwidth) / scaleFreq)) {
                fill(50, 0, 200); // Midrange Beta (Purple) (~16-20 Hz)
                stroke(75, 0, 175);
            }
            if (i >= round((betaCenter + betaBandwidth) / scaleFreq) + 1 &&
            i <= round(30 / scaleFreq)) {
                fill(0, 0, 250); // High Beta (Purple - Light Blue) (~20-30 Hz)
                stroke(25, 0, 225);
            }
            if (i >= round(32 / scaleFreq)) {
                fill(240, 240, 240); // Noise (30-60 Hz)
                stroke(200, 200, 200);
            }
            if (i == round(60 / scaleFreq)) {
                fill(200, 200, 200); // Color 60 Hz a different tone of grey,
                stroke(150, 150, 150); // to see how much noise is in data
            }
    
        // Draw the actual frequency bars
        rect(FFTrectWidth * i, FFTheight, FFTrectWidth * (i + 1), FFTheight - fft.getBand(i) * 20);
        }
    }
    // Divide the average by how many time points we have
    timeDomainAverage = timeDomainAverage / (windowWidth - 1);
}

// Give user textual information on data being thrown out and filters we have active
void displayText() {
    // Show user when data is being thrown out
    if (absoluteBadDataFlag == true) {
        fill(255, 0, 0);
        text("AbsoluteBadDataFlag = " + absoluteBadDataFlag, windowWidth - 200, 120);
        println("AbsoluteBadDataFlag = " + absoluteBadDataFlag);
        println(counter);
    } else {
        text("AbsoluteBadDataFlag = " + absoluteBadDataFlag, windowWidth - 200, 120);
    }
    
    if (averageBadDataFlag == true) {
        fill(255, 0, 0);
        text("AverageBadDataFlag = " + averageBadDataFlag, windowWidth - 200, 140);
        println("AverageBadDataFlag = " + averageBadDataFlag);
        println(counter);
    } else {
        text("AverageBadDataFlag = " + averageBadDataFlag, windowWidth - 200, 140);
    }

    // Show user when a filter is being applied to the data
    fill(255, 255, 255);
    text("Alpha filter is " + in.hasEffect(alphaFilter), windowWidth - 200, 160);
    text("Beta filter is " + in.hasEffect(betaFilter), windowWidth - 200, 180);
}

// Compute and display averages for each brain wave for the past ~5 seconds
void displayFreqAverages() {
    // Show averages of alpha, beta, etc. waves
    for (int i = 0; i < 6; i++) {
        float avg = 0; // Raw data for amplitude of section of frequency
        int lowFreq = 0;
        int hiFreq = 0;

        // Set custom frequency ranges to be averaged 
        if (i == 0) {
            lowFreq = 0;
            hiFreq = 3;
            fill(250, 0, 0);
            stroke(255, 0, 10);
        }
        if (i == 1) {
            lowFreq = 3;
            hiFreq = 7;
            fill(200, 0, 50);
            stroke(225, 0, 25);
        }
        if (i == 2) {
            lowFreq = alphaCenter - alphaBandwidth;
            hiFreq = alphaCenter + alphaBandwidth;
            fill(150, 0, 100);
            stroke(175, 0, 75);
        }
        if (i == 3) {
            lowFreq = 12;
            hiFreq = 15;
            fill(100, 0, 150);
            stroke(125, 0, 125);
        }
        if (i == 4) {
            lowFreq = betaCenter - betaBandwidth;
            hiFreq = betaCenter + betaBandwidth;
            fill(50, 0, 200);
            stroke(75, 0, 175);
        }
        if (i == 5) {
        lowFreq = 20;
        hiFreq = 30;
        fill(0, 0, 250);
        stroke(25, 0, 225);
        }
    
        // Convert frequencies to FFT bands. Because of our FFT parameters(256, 256),
        // these are equal (each band has a 1 Hz width).
        int lowBound = fft.freqToIndex(lowFreq);
        int hiBound = fft.freqToIndex(hiFreq);
    
        // Scale the band number, issue outlined at beginning of program
        lowBound = round(lowBound / scaleFreq);
        hiBound = round(hiBound / scaleFreq);
    
        // Get average for frequencies in range
        for (int j = lowBound; j <= hiBound; j++) {
            avg += fft.getBand(j);
        }
        avg /= (hiBound - lowBound + 1);
    
        // Scale the bars so that it fits our window better
        for (int k = 0; k < 6; k++) {
            if (i == k) {
                avg *= scaling[i] * freqAvgScale;
            }
        }
    
        // Update array for the moving average (only if our data is "good")
        if (absoluteBadDataFlag == false && averageBadDataFlag == false) {
            averages[i][counter % averageLength] = avg; // Populate 2D averages array with averages from previous loops
        }
    
        // Calculate the running average for each frequency range
        float sum = 0;
        for (int k = 0; k < averageLength; k++) {
            sum += averages[i][k]; // Adding to sum from 2D averages array
        }
        sum = sum / averageLength; // Averaging sum
    
        // Draw averaged/smoothed frequency ranges
        rect(i * width / 6, height, (i + 1) * width / 6, height - sum * 20);
    }
}

// Always close Minim audio classes when you are done with them
void stop() { 
    in.close();
    minim.stop();
    super.stop();
}
