
import java.util.Collections;
import java.util.Arrays;
import java.util.List; 

import oscP5.*;
import netP5.*;

OscP5 oscP5;
NetAddress myRemoteLocation;

final String oscIp = "127.0.0.1";
final int oscPort = 8000;


// class contains data for one frame
public class Frame {
  Frame() {
    points = new ArrayList<PVector>();
    visible = new ArrayList<Boolean>();
    center = new PVector();
  }

  float time;
  List<PVector> points;  // all points
  List<Boolean> visible;  // is i'th point visible or not

  PVector center;
}


List<Frame> frames;
String data_headers[];


// in cm
PVector camPos = new PVector(50, 400, 170);
PVector camLookAt = new PVector(0, 0, 100); //(look at around waist)
float camTheta = 0;
float camPhi = 0;
float camDistance = 400;
PVector smoothedCamPos = new PVector();
PVector smoothedCamLookAt = new PVector();
boolean camLookAtOrigin = true;


// playback
int playDir = 1;
int currentFrame = 0;
int numFrames = 0;


PFont f;


void setup() {
  size(800, 600, P3D);
  loadData();

  f = createFont("SansSerif", 12);
  textFont(f);
  
  data_headers = loadStrings("data_headers.txt");

  oscP5 = new OscP5(this, 0);
  myRemoteLocation = new NetAddress(oscIp, oscPort);
}



void draw() {
  background(0);

  pushMatrix();

  smoothedCamLookAt.lerp(camLookAt, 0.1);

  // set orbit camera based on mouse position
  {
    // convert spherical to cartesian
    camPos.x = camDistance * sin(camPhi) * cos(camTheta);
    camPos.y = camDistance * sin(camPhi) * sin(camTheta);
    camPos.z = camDistance* cos(camPhi);

    camPos.add(smoothedCamLookAt);
  }

  smoothedCamPos.lerp(camPos, 0.1);

  // set camera
  camera(smoothedCamPos.x, smoothedCamPos.y, smoothedCamPos.z, smoothedCamLookAt.x, smoothedCamLookAt.y, smoothedCamLookAt.z, 0, 0, -1);


  // draw floor grid
  {
    noFill();
    stroke(50);
    strokeWeight(1);
    float size = 10;  // cm 
    float num = 100;
    float start = -num/2 * size;
    float end = num/2 * size;
    for (float x=start; x<end; x+=size) {
      for (float y=start; y<end; y+=size) {
        rect(x, y, size, size);
      }
    }

    // draw axis
    stroke(100);
    strokeWeight(2);
    line(start, 0, end, 0);
    line(0, start, 0, end);
  }


  // cap currentFrame before using it
  currentFrame = constrain(currentFrame, 0, numFrames-1);

  // draw frame data
  if (frames!=null) {
    Frame frame = frames.get(currentFrame);

    // draw points
    for (int i=0; i<frame.points.size(); i++) {
      PVector p = frame.points.get(i);
      noFill();
      if (frame.visible.get(i)) {
        stroke(0, 255, 0);
        strokeWeight(5);
      } 
      else {
        stroke(120, 20, 20);
        strokeWeight(3);
      }
      point(p.x, p.y, p.z);
    }

    // draw center
    stroke(0, 0, 150);
    strokeWeight(1);
    pushMatrix();
    translate(frame.center.x, frame.center.y, frame.center.z);
    box(6);
    popMatrix();

    // set camera look at
    if (camLookAtOrigin) camLookAt.set(0, 0, 100);
    else camLookAt.set(frame.center);

    // send Osc
    sendOsc(frame);

    // advance playhead
    currentFrame += playDir;
  }

  popMatrix();

  // draw playhead
  {
    fill(255);
    noStroke();
    rect(0.0, height - 5.0, map(currentFrame, 0, numFrames, 0, width), 5.0);
  }

  // draw text
  {
    fill(200);
    String s = "";
    s += "l - load new data file\n";
    s += "SPACE - toggle play / pause \n";
    s += "> - play forwards\n";
    s += "< - play backwards\n";
    s += ". - next frame\n";
    s += ", - previous frame\n";
    s += "w - rewind\n";
    s += "o - toggle between looking at world center, or center of the dancer\n";
    s += "] - zoom in\n";
    s += "[ - zoom out\n";

    textAlign(LEFT, TOP);
    text(s, 10, 10);
  }
}


void loadData() {
  selectInput("Select a file to process:", "fileSelected");
}

void fileSelected(File selection) {
  if (selection == null) {
    println("Window was closed or the user hit cancel.");
  } 
  else {
    println("User selected " + selection.getAbsolutePath());

    // load file
    String data[] = loadStrings(selection.getAbsolutePath());

    // dump headers
    println("\n-----------------------------------");
    println("Headers:");

    List<String> headers = getStringListForRow(data, 3);
    for (int i=0; i<headers.size(); i++) {
      String s = headers.get(i);
      println(i + " : " + s);
    }


    // clear frames
    frames = new ArrayList<Frame>();

    // load all frames (starting at row 5)
    println("\n-----------------------------------");
    println("Processing frames....");
    int startRow = 5;
    for (int r=startRow; r<data.length; r++) {
      print("   frame: " + (r - startRow) + "   ");
      // get string list for row
      List<String> strings = getStringListForRow(data, r);
      if (strings.size() > 0) {

        // create new float array
        float floats[] = new float[strings.size()];

        // iterate all string components of row
        for (int i=0; i<strings.size(); i++) {

          // convert to float and add to floats array
          floats[i] = Float.parseFloat(strings.get(i));
        }

        // create new frame
        Frame frame = new Frame();

        // bit of a hack. subtract time, then divide by 4 to get number of points
        int numPoints = (floats.length - 1) / 4;

        // save frametime
        frame.time = floats[0];

        int numVisible = 0;
        for (int i=0; i<numPoints; i++) {
          int startIndex = i*4+1;
          float scaler = 0.1;  // convert to cm
          PVector p = new PVector(floats[startIndex] * scaler, floats[startIndex+1] * scaler, floats[startIndex+2] * scaler);
          frame.points.add(p);

          boolean visible = floats[startIndex + 3] > 0;
          if (visible) {
            numVisible++;
            frame.center.add(p);
            print("|");
          } 
          else {
            print(".");
          }
          frame.visible.add(visible);
        }

        frames.add(frame);
        println("   " + numVisible * 100.0/numPoints + "% visible");
        if (numVisible > 0) frame.center.mult(1.0/numVisible);
      } 
      else {
        println("no strings");
      }
    }

    currentFrame = 0;
    numFrames = frames.size();
  }
}

String getStringForRow(String data[], int rowIndex) {
  return data[rowIndex];
}

List<String> getStringListForRow(String data[], int rowIndex) {
  String [] strings = getStringForRow(data, rowIndex).split("\\s+");
  List<String> stringList = Arrays.asList(strings);
  return stringList;
}

void sendOsc(Frame frame) {
  if (frame != null) {
    OscBundle myBundle = new OscBundle();

    for (int i=0; i<frame.points.size(); i++) {
      PVector p = frame.points.get(i);
      if (frame.visible.get(i)) {
        String jointname = data_headers[i];
        String userId = "1";
        String oscAddress = "/daikon/user/" + userId + "/skeleton/" + jointname + "/pos";

        OscMessage myMessage = new OscMessage(oscAddress);
        myMessage.add(p.x);
        myMessage.add(p.y);
        myMessage.add(p.z);
        myBundle.add(myMessage);
      }
    }

    oscP5.send(myBundle, myRemoteLocation);
  }
}


void keyPressed() {
  switch(key) {
  case 'l':   // ask for new file to load
    loadData(); 
    break;

  case 'o':  // toggle between looking at world center, or center of the dancer
    camLookAtOrigin ^= true;
    break;

  case '[':
    camDistance += 50;
    break;

  case ']':
    if (camDistance > 100) camDistance -= 50;
    break;

  case ' ':  // toggle play / pause
    if (playDir != 0) playDir = 0;
    else playDir = 1;
    break;

  case '>':  // play forwards
    playDir = 1;
    break;

  case '<':  // play backwards
    playDir = -1;
    break;

  case '.':  // next frame
    playDir = 0;
    currentFrame ++;
    break;

  case ',':  // previous frame
    playDir = 0;
    currentFrame--;
    break;

  case 'w':  // rewind
    currentFrame = 0;
    break;
  }
}

void mousePressed() {
  mouseDragged();
}

void mouseMoved() {
  mouseDragged();
}

void mouseDragged() {
  camTheta = map(mouseX, 0, width, -PI, PI);
  camPhi = map(mouseY, 0, height, PI, 0);
}

