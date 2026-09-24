/**
 * @file ft5316_ts.c
 * @author wushuzhilu (lingzhi_gong@foxmail.com)
 * @brief 
 * @version 1.0
 * @date 2025-03-17
 * 
 * @copyright Copyright (c) 2025
 * 
 */
#include <linux/module.h>
#include <linux/i2c.h>
#include <linux/input.h>
#include <linux/input/mt.h>
#include <linux/of_gpio.h>
#include <linux/delay.h>
#include <linux/interrupt.h>
#include <linux/of.h>
#include <linux/regmap.h>
#include <linux/err.h>

/* FT5316寄存器定义 */
#define FT5316_DEVICE_MODE       0x00    /* 设备模式寄存器 */
#define FT5316_TD_STATUS         0x02    /* 触摸点状态寄存器 */
#define FT5316_TOUCH1_XH         0x03    /* 第一个触摸点X坐标高位 */
#define FT5316_ID_G_MODE         0xA4    /* 中断模式控制寄存器 */
#define FT5316_REG_FOCALTECH_ID  0xA3    /* FocalTech ID */
#define FT5316_REG_CHIP_ID_H     0xA5    /* Chip ID high byte */
#define FT5316_REG_CHIP_ID_L     0xA6    /* Chip ID low byte */

#define FT5316_MAX_SUPPORT_POINTS    5    /* 最大支持触摸点数 */
/* 触摸事件类型 */
#define FT5316_EVENT_DOWN            0x00 /* 按下事件 */
#define FT5316_EVENT_UP              0x01 /* 抬起事件 */
#define FT5316_EVENT_CONTACT         0x02 /* 接触事件 */
#define FT5316_EVENT_RESERVED        0x03 /* 保留事件 */

/**
 * 设备数据结构体
 * @client: I2C client device
 * @input_dev: Input device structure
 * @reset_gpio: 复位gpio
 * @irq_gpio: 中断gpio
 * @max_x: X轴最大分辨率
 * @max_y: Y轴最大分辨率
 * @inverted_x: X轴反转标志
 * @inverted_y: Y轴反转标志
 * @swapped_xy: X/Y轴交换标志
 */
struct ft5316_dev {
    struct i2c_client *client;
    struct input_dev *input_dev;
    int reset_gpio;
    int irq_gpio;
    u32 max_x;    
    u32 max_y;    
    bool inverted_x;  
    bool inverted_y;  
    bool swapped_xy;  
};

/**
 * @name ft5316_write_reg
 * @brief 向FT5316寄存器写数据
 * 
 * @param ft5316 设备私有数据
 * @param reg 寄存器地址
 * @param val 要写入的数据
 * @return int: 成功返回0，失败返回负数错误码
 */
static int ft5316_write_reg(struct ft5316_dev *ft5316, u8 reg, u8 val)
{
    struct i2c_client *client = ft5316->client;
    u8 data[2] = {reg, val};
    int ret;
    // dev_dbg(&client->dev, "FT5316: Writing 0x%02x to register 0x%02x\n", val, reg);
    ret = i2c_master_send(client, data, sizeof(data));
    if (ret != sizeof(data)) 
    {
        dev_err(&client->dev, "FT5316: I2C write error, reg=0x%x, val=0x%x, ret=%d (expected %zu bytes, got %d)\n",
                reg, val, ret, sizeof(data), ret);
        return ret < 0 ? ret : -EIO;
    }
    // dev_dbg(&client->dev, "FT5316: Write to register 0x%02x completed successfully\n", reg);
    return 0;
}

/**
 * @name ft5316_read_reg
 * @brief 从FT5316寄存器读数据
 * 
 * @param ft5316 设备私有数据
 * @param reg 寄存器地址
 * @param val 存储读取数据的缓冲区
 * @param len 要读取的字节数
 * @return int: 成功返回0，失败返回负数错误码
 */
static int ft5316_read_reg(struct ft5316_dev *ft5316, u8 reg, u8 *val, u16 len)
{
    struct i2c_client *client = ft5316->client;
    struct i2c_msg msg[2];
    int ret;
    // dev_dbg(&client->dev, "FT5316: Reading %d bytes from register 0x%02x\n", len, reg);
    msg[0].addr = client->addr;
    msg[0].flags = 0;
    msg[0].buf = &reg;
    msg[0].len = 1;

    msg[1].addr = client->addr;
    msg[1].flags = I2C_M_RD;
    msg[1].buf = val;
    msg[1].len = len;

    ret = i2c_transfer(client->adapter, msg, 2);
    if (ret != 2) 
    {
        dev_err(&client->dev, "FT5316: I2C read error, reg=0x%x, ret=%d (expected 2 transfers, got %d)\n", 
                reg, ret, ret);
        return ret < 0 ? ret : -EIO;
    }

    // dev_dbg(&client->dev, "FT5316: Read from register 0x%02x completed successfully\n", reg);
    /* debug用 */
    // if (len <= 4 && val) {
    //     dev_dbg(&client->dev, "FT5316: Read data: ");
    //     for (i = 0; i < len; i++) {
    //         dev_dbg(&client->dev, "0x%02x ", val[i]);
    //     }
    //     dev_dbg(&client->dev, "\n");
    // }

    return 0;
}

/**
 * @name ft5316_hw_reset
 * @brief 硬件复位FT5316
 * 
 * @param ft5316 设备私有数据
 * @return int : 成功返回0，失败返回负数错误码
 */
static int ft5316_hw_reset(struct ft5316_dev *ft5316)
{
    struct device *dev = &ft5316->client->dev;
    int ret;

    /* 设备树获取复位IO */
    ft5316->reset_gpio = of_get_named_gpio(ft5316->client->dev.of_node, "reset-gpios", 0);
    if (!gpio_is_valid(ft5316->reset_gpio)) 
    {
        dev_err(dev, "FT5316: Failed to get reset GPIO\n");
        return ft5316->reset_gpio;
    }

    ret = devm_gpio_request_one(dev, ft5316->reset_gpio,
                               GPIOF_OUT_INIT_HIGH, "ft5316-reset");
    if (ret < 0) 
    {
        dev_err(dev, "FT5316: Failed to request reset GPIO: %d\n", ret);
        return ret;
    }

    /* 复位 */
    msleep(20);
    gpio_set_value_cansleep(ft5316->reset_gpio, 0);
    msleep(5);
    gpio_set_value_cansleep(ft5316->reset_gpio, 1);
    msleep(50); 

    return 0;
}

/**
 * @name ft5316_parse_dt
 * @brief 解析设备树
 * 
 * @param ft5316 设备私有数据
 * @return int: 成功返回0，失败返回负数错误码
 */
static int ft5316_parse_dt(struct ft5316_dev *ft5316)
{
    struct device_node *np = ft5316->client->dev.of_node;
    int ret;

    /* 设备树获取触摸分辨率 */
    ret = of_property_read_u32(np, "touchscreen-size-x", &ft5316->max_x);
    if (ret) 
    {
        dev_warn(&ft5316->client->dev, "FT5316: Failed to get touchscreen-size-x, using default 480\n");
        ft5316->max_x = 480;
    }

    ret = of_property_read_u32(np, "touchscreen-size-y", &ft5316->max_y);
    if (ret) 
    {
        dev_warn(&ft5316->client->dev, "FT5316: Failed to get touchscreen-size-y, using default 800\n");
        ft5316->max_y = 800;
    }

    /* 触摸反转设置 */
    ft5316->inverted_x = of_property_read_bool(np, "touchscreen-inverted-x");
    ft5316->inverted_y = of_property_read_bool(np, "touchscreen-inverted-y");
    ft5316->swapped_xy = of_property_read_bool(np, "touchscreen-swapped-x-y");

    dev_info(&ft5316->client->dev, "FT5316: Touch screen resolution %ux%u\n",
             ft5316->max_x, ft5316->max_y);
    
    dev_info(&ft5316->client->dev, "FT5316: Touch screen orientation inverted-x=%d, inverted-y=%d, swapped-xy=%d\n",
             ft5316->inverted_x, ft5316->inverted_y, ft5316->swapped_xy);

    return 0;
}

/**
 * @name ft5316_ts_irq_handler
 * @brief 中断处理函数
 * 
 * @param irq 中断号
 * @param dev_id 设备私有数据
 * @return irqreturn_t: IRQ_HANDLED
 */
static irqreturn_t ft5316_ts_irq_handler(int irq, void *dev_id)
{
    struct ft5316_dev *ft5316 = dev_id;
    u8 touch_data[29] = {0};
    int i, ret;

    /* 读取数据 */
    ret = ft5316_read_reg(ft5316, FT5316_TD_STATUS, touch_data, sizeof(touch_data));
    if (ret < 0) 
    {
        dev_err(&ft5316->client->dev, "FT5316: Failed to read touch data: %d\n", ret);
        return IRQ_HANDLED;
    }

    /* 处理每个触摸点 */
    for (i = 0; i < FT5316_MAX_SUPPORT_POINTS; i++) 
    {
        u8 *touch_point = &touch_data[i * 6 + 1];
        u8 event_flag = (touch_point[0] >> 6) & 0x03;
        u8 touch_id = (touch_point[2] >> 4) & 0x0f;
        u16 x = ((touch_point[0] & 0x0f) << 8) | touch_point[1];
        u16 y = ((touch_point[2] & 0x0f) << 8) | touch_point[3];
        u16 reported_x, reported_y;

        /* 跳过保留状态的触摸点 */
        if (event_flag == FT5316_EVENT_RESERVED) continue;

        if (ft5316->swapped_xy) 
        {
            /* 交换xy */
            reported_x = y;
            reported_y = x;
            
            if (ft5316->inverted_x) reported_x = ft5316->max_x - reported_x; /* x反转 */
            if (ft5316->inverted_y) reported_y = ft5316->max_y - reported_y; /* y反转 */
        } else 
        {
            /* 不交换xy */
            reported_x = ft5316->inverted_x ? (ft5316->max_x - x) : x;
            reported_y = ft5316->inverted_y ? (ft5316->max_y - y) : y;
        }

        /* 报告多点触摸信息 */
        input_mt_slot(ft5316->input_dev, touch_id);
        input_mt_report_slot_state(ft5316->input_dev, MT_TOOL_FINGER,
                                  event_flag != FT5316_EVENT_UP);

        if (event_flag != FT5316_EVENT_UP) 
        {
            /* 报告坐标信息 */
            input_report_abs(ft5316->input_dev, ABS_MT_POSITION_X, reported_x);
            input_report_abs(ft5316->input_dev, ABS_MT_POSITION_Y, reported_y);
        }
    }

    /* 结束报告 */
    input_mt_report_pointer_emulation(ft5316->input_dev, true);
    input_sync(ft5316->input_dev);

    return IRQ_HANDLED;
}
 
/**
 * @name ft5316_setup_irq
 * @brief 设置中断
 * 
 * @param ft5316 设备私有数据
 * @return int: 成功返回0，失败返回负数错误码
 */
static int ft5316_setup_irq(struct ft5316_dev *ft5316)
{
    struct device *dev = &ft5316->client->dev;
    int ret;

    /* 设备树获取中断GPIO */
    ft5316->irq_gpio = of_get_named_gpio(ft5316->client->dev.of_node, 
                                        "irq-gpios", 0);
    if (!gpio_is_valid(ft5316->irq_gpio)) 
    {
        dev_err(dev, "FT5316: Failed to get IRQ GPIO\n");
        return ft5316->irq_gpio;
    }

    ret = devm_gpio_request_one(dev, ft5316->irq_gpio, GPIOF_IN, "ft5316-irq");
    if (ret < 0) 
    {
        dev_err(dev, "FT5316: Failed to request IRQ GPIO: %d\n", ret);
        return ret;
    }

    /* 注册中断处理函数 */
    ret = devm_request_threaded_irq(dev, gpio_to_irq(ft5316->irq_gpio),
                                   NULL, ft5316_ts_irq_handler,
                                   IRQF_TRIGGER_FALLING | IRQF_ONESHOT,
                                   "ft5316-ts", ft5316);
    if (ret < 0) 
    {
        dev_err(dev, "FT5316: Failed to request IRQ: %d\n", ret);
        return ret;
    }

    return 0;
}

/**
 * @name ft5316_probe
 * @brief I2C设备注册
 * 
 * @param client I2C客户端
 * @param id I2C设备ID
 * @return int: 成功返回0，失败返回负数错误码
 */
static int ft5316_probe(struct i2c_client *client, const struct i2c_device_id *id)
{
    struct ft5316_dev *ft5316;
    struct input_dev *input_dev;
    int ret;
    // u8 test_reg;

    // dev_info(&client->dev, "FT5316: probe started\n");
    // dev_info(&client->dev, "FT5316: I2C address: 0x%02x\n", client->addr);

    /* 检查I2C适配器功能 */
    if (!i2c_check_functionality(client->adapter, I2C_FUNC_I2C)) 
    {
        dev_err(&client->dev, "FT5316: I2C adapter doesn't support I2C_FUNC_I2C\n");
        return -ENODEV;
    }

    ft5316 = devm_kzalloc(&client->dev, sizeof(*ft5316), GFP_KERNEL);
    if (!ft5316) 
    {
        dev_err(&client->dev, "FT5316: Failed to allocate device data (ENOMEM)\n");
        return -ENOMEM;
    }

    ft5316->client = client;
    i2c_set_clientdata(client, ft5316);

    /* 测试I2C通信 */
    // ret = ft5316_read_reg(ft5316, FT5316_DEVICE_MODE, &test_reg, 1);
    // if (ret < 0) 
    // {
    //     dev_err(&client->dev, "FT5316: I2C communication test failed: %d\n", ret);
    //     return ret;
    // }
    // dev_info(&client->dev, "FT5316: I2C communication test successful, MODE register=0x%02x\n", test_reg);

    // dev_dbg(&client->dev, "FT5316: Parsing device tree...\n");
    ret = ft5316_parse_dt(ft5316);
    if (ret < 0) 
    {
        dev_err(&client->dev, "FT5316: Failed to parse device tree: %d\n", ret);
        return ret;
    }
    // dev_dbg(&client->dev, "FT5316: Device tree parsed successfully\n");

    // dev_dbg(&client->dev, "FT5316: Performing hardware reset...\n");
    /* 硬件复位 */
    ret = ft5316_hw_reset(ft5316);
    if (ret < 0) 
    {
        dev_err(&client->dev, "FT5316: Failed to reset device: %d\n", ret);
        return ret;
    }
    // dev_dbg(&client->dev, "FT5316: Hardware reset completed\n");

    // dev_dbg(&client->dev, "FT5316: Initializing registers...\n");
    /* 初始化FT5316 */
    ret = ft5316_write_reg(ft5316, FT5316_DEVICE_MODE, 0x00); /* 正常模式 */
    if (ret < 0) 
    {
        dev_err(&client->dev, "FT5316: Failed to set device mode: %d\n", ret);
        return ret;
    }
    // dev_dbg(&client->dev, "FT5316: Device mode set to 0x00 (normal mode)\n");

    ret = ft5316_write_reg(ft5316, FT5316_ID_G_MODE, 0x01); /* 中断模式 */
    if (ret < 0) 
    {
        dev_err(&client->dev, "FT5316: Failed to set interrupt mode: %d\n", ret);
        return ret;
    }
    // dev_dbg(&client->dev, "FT5316: Interrupt mode set to 0x01\n");

    /* 读取寄存器确认 */
    // ret = ft5316_read_reg(ft5316, FT5316_DEVICE_MODE, &test_reg, 1);
    // if (ret < 0) 
    // {
    //     dev_err(&client->dev, "FT5316: Failed to verify device mode: %d\n", ret);
    //     return ret;
    // }
    // dev_dbg(&client->dev, "FT5316: Verified DEVICE_MODE register=0x%02x\n", test_reg);

    // dev_dbg(&client->dev, "FT5316: Setting up IRQ...\n");
    /* 设置中断 */
    ret = ft5316_setup_irq(ft5316);
    if (ret < 0) 
    {
        dev_err(&client->dev, "FT5316: Failed to setup IRQ: %d\n", ret);
        return ret;
    }
    // dev_dbg(&client->dev, "FT5316: IRQ setup completed\n");

    // dev_dbg(&client->dev, "FT5316: Allocating input device...\n");
    /* 初始化输入设备 */
    input_dev = devm_input_allocate_device(&client->dev);
    if (!input_dev) 
    {
        dev_err(&client->dev, "FT5316: Failed to allocate input device (ENOMEM)\n");
        return -ENOMEM;
    }

    ft5316->input_dev = input_dev;
    input_dev->name = "FT5316 Touchscreen";
    input_dev->id.bustype = BUS_I2C;
    input_dev->dev.parent = &client->dev;
    // dev_dbg(&client->dev, "FT5316: Input device allocated\n");

    // dev_dbg(&client->dev, "FT5316: Setting input device properties...\n");
    /* 设置输入设备属性 */
    __set_bit(EV_ABS, input_dev->evbit);
    __set_bit(EV_KEY, input_dev->evbit);
    __set_bit(BTN_TOUCH, input_dev->keybit);

    /* 设置多点属性 */
    input_set_abs_params(input_dev, ABS_MT_POSITION_X, 0, ft5316->max_x, 0, 0);
    input_set_abs_params(input_dev, ABS_MT_POSITION_Y, 0, ft5316->max_y, 0, 0);
    input_set_abs_params(input_dev, ABS_MT_TOUCH_MAJOR, 0, 255, 0, 0);
    // dev_dbg(&client->dev, "FT5316: Input device properties set, resolution: %ux%u\n", 
    //         ft5316->max_x, ft5316->max_y);

    // dev_dbg(&client->dev, "FT5316: Initializing MT slots...\n");
    /* 初始化多点触摸*/
    ret = input_mt_init_slots(input_dev, FT5316_MAX_SUPPORT_POINTS, INPUT_MT_DIRECT);
    if (ret < 0) 
    {
        dev_err(&client->dev, "FT5316: Failed to init MT slots: %d\n", ret);
        return ret;
    }
    // dev_dbg(&client->dev, "FT5316: MT slots initialized\n");

    // dev_dbg(&client->dev, "FT5316: Registering input device...\n");
    /* 注册输入设备 */
    ret = input_register_device(input_dev);
    if (ret < 0) 
    {
        dev_err(&client->dev, "FT5316: Failed to register input device: %d\n", ret);
        return ret;
    }

    dev_info(&client->dev, "FT5316: touchscreen driver probed successfully!\n");
    return 0;
}

/**
 * @name ft5316_remove 
 * @brief I2C设备移除
 * 
 * @param client I2C客户端
 */
static void ft5316_remove(struct i2c_client *client)
{
    /* 无需处理 */
    dev_info(&client->dev, "FT5316: touchscreen driver removed\n");
    // return 0;
}

static const struct of_device_id ft5316_of_match[] = {
    { .compatible = "focaltech,ft5316" },
    { },
};
MODULE_DEVICE_TABLE(of, ft5316_of_match);

static const struct i2c_device_id ft5316_id[] = {
    { "ft5316", 0 },
    { },
};
MODULE_DEVICE_TABLE(i2c, ft5316_id);

/* I2C驱动结构体 */
static struct i2c_driver ft5316_driver = {
    .driver = {
        .name = "ft5316",
        .of_match_table = ft5316_of_match,
        .owner = THIS_MODULE,
    },
    .probe = ft5316_probe,
    .remove = ft5316_remove,
    .id_table = ft5316_id,
};

module_i2c_driver(ft5316_driver);

MODULE_DESCRIPTION("FT5316 Touchscreen Driver");
MODULE_AUTHOR("wushuzhilu");
MODULE_LICENSE("GPL v3");
MODULE_VERSION("1.0");