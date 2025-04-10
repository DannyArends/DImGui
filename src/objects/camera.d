import engine;

import vector : normalize, vMul, vAdd, negate, xyz;
import matrix : Matrix, multiply, rotate, radian;
import quaternion : xyzw;

struct Camera {
    float[3]     position    = [-1.0f, 0.0f, 0.0f];  // Position
    float[3]     lookat      = [0.0f, 0.0f, 0.0f];    // Position in the middle of the screen
    float[2]     nearfar     = [0.1f, 100.0f];        // View distances, near [0], far [1]
    float[3]     up          = [0.0f, 0.0f, 1.0f];    // Defined up vector
    float        fov         = 45.0f;                 // Field of view

    float[3]     rotation    = [180.0f, 0.0f, 0.0f];    // Horizontal [0], Vertical [1]
    float        distance    = -1.0f;                 // Distance of camera to lookat
    
    bool[2]      isdrag        = [false, false];

    // Move the camera forward
    @property float[3] forward() const { 
      float[3] direction = rotation.direction();
      direction[2] = 0.0f;
      direction.normalize();
      direction = direction.vMul(0.1f);
      return(direction);
    }

    // Move the camera backward
    @property float[3] back() const { 
      float[3] back = -forward()[];
      return(back);
    }

    // Move the camera to the left of the view direction
    @property float[3] left() const {
      float[3] direction = forward();
      float[3] left = multiply(rotate(Matrix.init, [-90.0f, 0.0f, 0.0f]), direction.xyzw()).xyz;
      return(left);
    }

    // Move the camera to the right of the view direction
    @property float[3] right() const { 
      float[3] right = -left()[];
      return(right);
    }
}

/* Get the normalized direction of the xy camera rotation (gimbal lock) */
float[3] direction(const float[3] rotation) {
    float[3] direction = [
        cos(radian(rotation[1])) * cos(radian(rotation[0])),
        cos(radian(rotation[1])) * sin(radian(rotation[0])),
        sin(radian(rotation[1]))
    ];
    direction.normalize();
    direction.negate();
    return(direction);
}

void move(ref Camera camera, float[3] movement) {
    camera.lookat = vAdd(camera.lookat, movement);
    camera.position = vAdd(camera.lookat, vMul(camera.rotation.direction(), camera.distance));
    //SDL_Log("%s", toStringz(format("%s", camera.position)));
    //SDL_Log("%s", toStringz(format("%s", camera.lookat)));
}

/* Drag the camera in the x/y directions, causes camera rotation */
void drag(ref Camera camera, float xrel, float yrel) {
    camera.rotation[0] -= xrel; 
    if(camera.rotation[0]  > 360) camera.rotation[0] = 0;
    if(camera.rotation[0]  < 0) camera.rotation[0] = 360;

    camera.rotation[1] += yrel;
    if(camera.rotation[1]  > 65) camera.rotation[1] = 65;
    if(camera.rotation[1]  < -65) camera.rotation[1] = -65;

    camera.move([0.0f, 0.0f, 0.0f]);
}

